# Plan: git credential helper for actions-runner (Puppet side)

This is the **Puppet side** of a three-repo change. The companion plan, with the problem statement, the
security model, and the Terraform and Lambda work, lives in `terraform-aws-actions-runner`:
`.claude/plans/git-credentials-for-private-repos.md`.

## Why

A job on a self-hosted runner can check out the repository that triggered it, because `actions/checkout` uses
the per-repo `GITHUB_TOKEN`. It cannot reach any other private repository in the same organisation. Anything
that resolves dependencies by shelling out to git — `terraform init` against a private module, `go mod
download`, `git submodule update`, `pip install git+https://…` — fails unless the workflow first plumbs a
GitHub App token into a throwaway gitconfig by hand, in every repository that needs it.

We fix it once on the runner instead of in every workflow, by registering a git credential helper in the system
gitconfig. Tools that shell out to git then authenticate transparently, and no workflow mentions credentials.

## What Terraform provides (dependency)

1. A token-minting Lambda. It resolves the GitHub App installation for the org and returns a one-hour token
   with `contents: read` only, optionally restricted to an allowlist of repositories.
2. `lambda:InvokeFunction` on that one function, added to the runner instance profile.
3. A new Puppet custom fact `git_credentials_lambda`, injected via cloud-init external facts — the same
   mechanism as the existing `registration_token_secret_prefix` and `deregistration_hookname` facts.

**There is no enable flag.** Once a pool takes the Terraform major version, the fact is always set. The guard
below is therefore not an opt-out — it is version-skew tolerance. Runners built from an older module emit no
such fact, and this repo ships to global before the Terraform side does, so for a period every runner Puppet
converges will be one that does not set it. It must converge cleanly and simply not install the helper.

## What infrahouse-toolkit provides (dependency)

`ih-github credential-helper` — reads git's credential protocol on stdin, invokes the Lambda, writes
`username` / `password` on stdout, and caches tokens in `/dev/shm`. The toolkit is already installed on every
runner and already used by `profile::github_runner::register`.

## Changes in this repo

### 1. New class `profile::github_runner::git_credentials`

```puppet
# @summary: configures git to authenticate to GitHub via the credential helper.
class profile::github_runner::git_credentials (
  $lambda_name,
  $user,
) {
  $helper_path = '/usr/local/bin/gha-git-credential'

  file { $helper_path:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    content => template('profile/github_runner/gha-git-credential.erb'),
  }

  # System-wide, so it applies regardless of which user the job's steps run as.
  # useHttpPath passes <org>/<repo> to the helper, which is what makes
  # per-repository token scoping possible.
  exec { 'git_credential_helper':
    path    => '/usr/bin:/usr/local/bin',
    command => "git config --system credential.https://github.com.helper ${helper_path}",
    unless  => "git config --system --get credential.https://github.com.helper | grep -qx ${helper_path}",
    require => File[$helper_path],
  }

  exec { 'git_credential_usehttppath':
    path    => '/usr/bin:/usr/local/bin',
    command => 'git config --system credential.https://github.com.useHttpPath true',
    unless  => 'git config --system --get credential.https://github.com.useHttpPath | grep -qx true',
    require => Exec['git_credential_helper'],
  }
}
```

### 2. New template `templates/github_runner/gha-git-credential.erb`

A thin wrapper so the Lambda name is baked in rather than discovered at run time:

```bash
#!/usr/bin/env bash
# Git credential helper. Git invokes this with the operation as $1 and the
# credential description on stdin. Only "get" is meaningful to us; "store"
# and "erase" are no-ops because we mint tokens on demand and never persist
# them outside tmpfs.
set -eu
exec /usr/local/bin/ih-github credential-helper \
  --lambda-name "<%= @lambda_name %>" \
  "$@"
```

Keep the logic in the toolkit, not in the shell wrapper. Shell here is a shim only.

### 3. Wire it into `profile::github_runner`

In `manifests/github_runner.pp`, after the `register` class:

```puppet
$git_credentials_lambda = $facts['git_credentials_lambda']

if $git_credentials_lambda and !empty($git_credentials_lambda) {
  class { 'profile::github_runner::git_credentials':
    lambda_name => $git_credentials_lambda,
    user        => $user,
  }
}
```

### 4. Clear the token cache in `gha_postrun.sh`

Tokens live in tmpfs and expire within the hour, but a runner is not ephemeral — it serves the next job with the
same filesystem. Do not leave one job's credentials readable by the next.

```bash
#!/usr/bin/env bash

set -eu

rm -rf /dev/shm/gha-git-credential-cache

/usr/local/bin/ih-aws autoscaling scale-in disable-protection
```

Order matters: clear the cache first. `disable-protection` can be the last thing that happens before the
instance is selected for scale-in, and we want the cache gone regardless.

Use `rm -rf` without a guard so the hook stays idempotent on a runner from an older module version, where the
helper was never installed and the directory never existed. The hook runs under `set -eu`, so anything added
here must not fail on a clean instance.

## Interaction with hibernation

Warm-pool instances are hibernated immediately after provisioning and resume later. Two consequences:

- **The system gitconfig survives** — it is on disk, written during the Puppet run, and is correct on resume.
  Nothing needs to re-run.
- **`/dev/shm` does not survive** a hibernate/resume cycle in any form we should rely on. That is fine: the
  cache is an optimisation and the helper re-mints on a miss. Do not put anything durable there.

There is no need to re-register the helper on resume, so this class does not need to be idempotent against a
warm-pool wake beyond ordinary Puppet idempotency.

## Testing

1. Puppet applies cleanly on a runner with the fact set, and the system gitconfig contains both entries.
2. Puppet applies cleanly with the fact **absent**, and no gitconfig entry is created. This is every runner
   built from an older module version, which is all of them until the Terraform major lands — so it must be
   verified, not assumed.
3. `git clone https://github.com/<org>/<other-private-repo>` succeeds on the runner with no environment set up.
4. `terraform init` resolves a private module from another repository in the org.
5. A second clone in the same job does not invoke the Lambda (cache hit).
6. After a job completes, `/dev/shm/gha-git-credential-cache` does not exist.
7. Re-running Puppet does not churn the gitconfig (the `unless` guards hold).

## Rollout

Follow the established promotion path used for graceful scale-in:

1. `development` environment module.
2. Promote to `sandbox`.
3. Promote to global (`production`).

Each step gated on a runner in that environment cloning a second private repository successfully.

## Security note

Registering this helper means **every job on the pool can read every repository the App installation can see**,
narrowed only by the allowlist configured on the Terraform side. That is inherent to the feature, not a defect.

Do not enable it on any pool that runs untrusted pull requests. The full reasoning, and the list of what the
design does and does not bound, is in the companion plan.
