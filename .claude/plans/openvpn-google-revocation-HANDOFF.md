# Session handoff: OpenVPN cert revocation for deactivated Google users

Written before an IDE restart to preserve full context. Companion to the
design doc [`openvpn-google-user-revocation.md`](openvpn-google-user-revocation.md).
Date: 2026-07-19.

## The goal (recap)

Periodically check Google Workspace and **revoke the OpenVPN certificate** of
any user who has been suspended/deleted. Closes the gap where a deactivated
user can't mint a new cert (portal blocks login) but their already-downloaded
`.ovpn` keeps working until the CA revokes it.

## Key facts established (don't re-derive)

- **Certs are minted by the portal**, not Puppet:
  `terraform-aws-openvpn/portal/portal/__init__.py` -> `ensure_certificate()` ->
  `easyrsa gen-req/sign-req` with `EASYRSA_REQ_CN = <google email>`.
  So **CN == Google email**. Confirmed with the user.
- PKI lives on shared **EFS** at `<config_dir>/pki/{issued/<email>.crt,
  private/<email>.key}`; `pki/index.txt` is the source of truth (`V`=valid,
  `R`=revoked).
- Revocation primitive already used by the monthly CRL cron in
  `puppet-code .../openvpn_server/config.pp:178` (`easyrsa revoke` + `gen-crl`,
  `EASYRSA_PASSIN=file:<dir>/ca_passphrase`). OpenVPN re-reads CRL per
  connection, no restart.
- Reconciliation is a pure set-diff: valid CNs in index.txt MINUS active
  Google users = certs to revoke.

## Decisions made

1. **Auth approach chosen: Workload Identity Federation (WIF), NOT a stored SA
   key.** User's words: "SA sounds like fucking 2012." No service-account key
   at rest anywhere.
2. The DWD-without-key mechanism is **`iamcredentials.signJwt`** (Google signs
   the domain-wide-delegation assertion server-side). Requires the federated
   principal to hold BOTH `roles/iam.workloadIdentityUser` AND
   `roles/iam.serviceAccountTokenCreator` on the SA.
3. The one step that **cannot** be Terraformed (no resource in
   `hashicorp/google`): authorizing the SA's client ID + directory scope in the
   Workspace Admin console (Security -> API controls -> Domain-wide delegation).
   Reduced to pasting one client ID; emitted as a TF output.
4. Whole feature gated behind `enable_google_directory_revocation` (default
   false) so existing module consumers are unaffected.

## Files I created / changed this session

### puppet-code (this repo)
- `.claude/plans/openvpn-google-user-revocation.md` — the design doc.
- `.claude/plans/openvpn-google-revocation-HANDOFF.md` — this file.
- **No manifests written yet.** The Puppet side (a
  `profile::openvpn_server::google_revocation_sync` class: Python sync script +
  daily cron + flock lock) is still TODO.

### terraform-aws-openvpn (`/Users/aleks/code/terraform/terraform-aws-openvpn`,
symlink of `.../infrahouse/terraform/terraform-aws-openvpn`)
- `terraform.tf` — added `google` provider (`~> 6.0`) to required_providers.
- `google-wif.tf` — **the main deliverable.** Stands up the GCP side:
  `google_project_service` (sts/iamcredentials/iam/admin), keyless
  `google_service_account.dir_reader`, `google_iam_workload_identity_pool` +
  `_provider.aws` (with ARN-normalizing attribute-mapping CEL + attribute
  condition locked to the instance role), the two `google_service_account_iam_member`
  bindings, the rendered keyless cred-config (`local.wif_credential_config`),
  plus feature variables and outputs.
  - NOTE: a linter reformatted this file (interpolation -> `format()`/`join()`);
    functionally identical, keep it.
- `spikes/dwd-wif/` — copied out of the ephemeral scratchpad so it survives:
  `dwd_wif_spike.py` (4-stage end-to-end proof of the AWS->GCP->DWD->Directory
  chain), `README.md` (gcloud/console setup + run instructions), `requirements.txt`.
  `py_compile` passes; needs `google-auth`+`requests` and a mapped EC2 role to run.

## Files present that I did NOT create (review on resume)

Appeared during the session (timestamps 07:50-08:39), likely parallel work:
- `test_data/google_wif/` — a root harness consuming the module with the
  feature enabled. **Has a live ~690KB `terraform.tfstate` (modified ~08:35-08:39)
  — an apply appears to have actually run against real AWS+GCP.** Check whether
  resources are still up and need `terraform destroy`.
- `tests/test_google_wif.py` — pytest integration test asserting the keyless
  federation was created (SA has no user-managed keys, pool+provider ACTIVE,
  both IAM bindings present). Uses ADC; skips if no ADC/project.
- Other modified files in `git status` I didn't touch: `.bumpversion.cfg`,
  `Makefile`, `README.md`, `docs/getting-started.md`, `requirements.txt`,
  `test_data/openvpn/.gitignore`, deleted `test_data/openvpn/nul`.

## Verification status

- `terraform fmt` — clean on my files.
- `terraform validate` — NOT completed by me (needs `terraform init` against the
  private `registry.infrahouse.com`; errored on module-not-installed before
  reaching my code). The presence of an applied `test_data/google_wif` state
  suggests it did init+apply successfully elsewhere — confirm.

### 2026-07-19 (later session): WIF chain VERIFIED END-TO-END ✅

Ran `sudo /opt/openvpn-wif/verify-wif.sh` on live instance `i-0bb32c31f4bf8d62f`
(t3a.small, us-west-2a, role `openvpn-xCxFB8oEqdFa0e86148bc5db9c6fc9b2b26ad5`)
over SSM. **All four tiers PASS.** The keyless AWS->GCP->DWD->Directory chain
works for real. Do not re-litigate this.

- Tier 1 instance ARN matches the provider's locked attribute_condition.
- Tier 2 federated token minted from the EC2 role, no key.
- Tier 3 SA impersonation works => both IAM bindings
  (`workloadIdentityUser` + `serviceAccountTokenCreator`) are effective.
- Tier 4 Directory API read succeeded as subject `aleks@infrahouse.com`.

**The manual Workspace DWD authorization is ALREADY DONE** — client id
`110312795661293035653` is authorized for
`.../auth/admin.directory.user.readonly`. This was listed as a pending blocker
above; it is not one. (Next step #3 in the old list is complete.)

Tier 4 returned `[]` for `isSuspended=true`; a follow-up probe listing all users
returned 3 real accounts (aleks/anton.naumenko/dmytro @infrahouse.com, none
suspended), confirming `[]` was a true negative and not a silent auth failure.
**Consequence for testing the Puppet side: there is currently no suspended user
in the directory to exercise the revocation path.** Either suspend a throwaway
account or unit-test the set-diff against a fixture.

### Open question #1 — ANSWERED (wiring)

Resolved *not* via `custom_facts` but via `extra_files`: `asg.tf` now does
`extra_files = concat(var.extra_files, local.wif_extra_files)`, gated so the list
is `[]` when the feature is off. New supporting files (created after the original
handoff was written): `templates/wif.env.tftpl` and `scripts/verify-wif.sh`.
Confirmed working — cloud-init delivered all three files to `/opt/openvpn-wif/`
(`google-wif.json`, `wif.env`, `verify-wif.sh`) on the live instance.

`wif.env` carries no secret; it exports `GOOGLE_APPLICATION_CREDENTIALS`,
`WIF_SA_EMAIL`, `WIF_SA_CLIENT_ID`, `WIF_EXPECTED_ROLE_ARN`, `WIF_ADMIN_SUBJECT`.
**The Puppet revocation script should source `/opt/openvpn-wif/wif.env`** rather
than re-plumbing any of these through Hiera.

Python note: the google libs live in the infrahouse-toolkit embedded venv
(`/opt/infrahouse-toolkit/embedded/bin/python3`), NOT system python3 — the distro
`python3-google-auth` is 1.5.x and lacks `external_account`/`impersonated_credentials`
entirely. The revocation script must use the embedded interpreter.

## Open questions for the user

1. Wire the cred-config JSON + SA email + admin subject into `asg.tf`
   `custom_facts` (gated) so the instance actually receives them? (Deferred —
   couples to the not-yet-written Puppet side; mind the 16KB userdata limit,
   already gzipped.)
2. Revoke immediately on suspension vs. a grace period (Hiera knob
   `profile::openvpn_server::revocation_grace_days`, default 0)?

## Next steps (resume here) — updated 2026-07-19 post-verification

Steps 3 (DWD authorization + prove the chain) and the open question #1 wiring are
DONE; see the verification section above. Remaining:

1. **Write the Puppet `profile::openvpn_server::google_revocation_sync`** (script
   + daily cron + flock). This is now the critical path — the auth substrate it
   depends on is proven. Source `/opt/openvpn-wif/wif.env`; use the toolkit
   embedded python; reuse the `easyrsa revoke` + `gen-crl` pattern already at
   `openvpn_server/config.pp:178` (`EASYRSA_PASSIN=file:<dir>/ca_passphrase`).
2. Decide open question #2 (immediate revoke vs. `revocation_grace_days`).
3. `terraform init && terraform validate` in terraform-aws-openvpn.
4. Update `openvpn-google-user-revocation.md` to reference the WIF Terraform
   instead of the old SA-key approach (the plan still describes Option A).
5. Housekeeping in terraform-aws-openvpn (see below).

## Puppet side — WRITTEN 2026-07-19

Design confirmed with the user: three external dependencies (terraform-aws-openvpn,
infrahouse-toolkit, Google Workspace config). Puppet must not fail before they are
satisfied and must self-activate once they are. Achieved by gating at RUNTIME in a
wrapper script, not at compile time in Puppet — the class only ever writes a file
and a cron entry, so it cannot fail anywhere.

Files — **in `environments/development/` only**, NOT in global `modules/`:
- `environments/development/modules/profile/manifests/openvpn_server/google_revocation_sync.pp`
- `environments/development/modules/profile/templates/openvpn_server/google-user-sync.sh.erb`
- wired into `environments/development/modules/profile/manifests/openvpn_server.pp`
  behind the fact check

**Promotion path (repo convention, see #278 -> #279 -> #281):** land in
`environments/development` first, then promote to `environments/sandbox`, then to
global `modules/` (= production, all environments). Originally written straight
into global `modules/` by mistake and relocated on 2026-07-19; global
`modules/profile/manifests/openvpn_server.pp` was reverted and is untouched.
Promoting = copying the two files to the next environment's
`modules/profile/{manifests,templates}/openvpn_server/` and adding the same
gated `if $facts.dig('openvpn', 'google_directory_revocation')` block to that
environment's `openvpn_server.pp`.

### Gating: each dependency at the level it can be observed

User directive: "why not pass a fact whether enable_google_directory_revocation
true or false? Then in puppet, configuration is trivial without playing with exit
codes?" Correct for dependency 1, and adopted — but it does NOT remove the exit
codes, because the three dependencies are observable at different times:

| Dependency | Terraform knows? | Gate |
|---|---|---|
| 1. Feature enabled | yes | fact `openvpn.google_directory_revocation` -> Puppet `if` at COMPILE time |
| 2. Toolkit has subcommand | no (own release cycle) | wrapper probes `--help` at RUNTIME |
| 3. Workspace DWD authorized | no (human in a console) | sync exits 78, wrapper maps to "not ready" |

Dependency 3 can never become a fact: authorizing the client id is a paste into
the Workspace admin console with no `hashicorp/google` resource behind it, so
`enable_google_directory_revocation` can be true for days before it is done.
Terraform side: `asg.tf` custom_facts now emits
`google_directory_revocation : var.enable_google_directory_revocation`.

### Two bugs found by end-to-end testing (wrapper driving the real toolkit)

1. **Wrapper did not pass `--config-dir`.** It checked the PKI under Puppet's
   `$openvp_config_directory` but invoked the toolkit with no `--config-dir`, so
   the toolkit silently used `/etc/openvpn` -- wrapper inspecting one PKI while
   the toolkit reconciled another. Fixed: single `CONFIG_DIR` variable in the
   template, used for both the index check and the invocation. NOTE the option is
   group-level, so it must precede the subcommand:
   `ih-openvpn --config-dir X sync-google-users`.
2. **`DefaultCredentialsError` was uncaught** -> traceback -> exit 1 -> the wrapper
   would have reported a real failure and mailed cron daily. This is the exact
   failure mode the whole design exists to avoid. Hit whenever the credential
   config is missing/malformed or IMDS is unreachable. Fixed: translated to
   `GoogleNotConfigured` -> 78. Regression test:
   `test_default_credentials_error_becomes_not_configured`.

Both were invisible to unit tests and only surfaced by running the rendered
wrapper against the actual installed CLI. Keep doing that.

Decisions (user-confirmed):
- Sync logic goes in the **toolkit**, not Puppet: new `ih-openvpn sync-google-users`.
  Puppet owns only gate + flock + cron. Keeps the set-diff unit-testable in CI and
  reuses existing `cmd_revoke_client` / index.txt parsing.
- **Immediate revocation**, stateless set-diff. No grace period, nothing persisted.
- **NO dry-run / report-only mode.** User directive: "if
  `enable_google_directory_revocation` is true, we enforce." A report-only stage was
  designed and then explicitly cut. Do not reintroduce it.
  - Consequence: no enforcement flag anywhere — no Hiera key, no custom fact, no new
    Terraform variable, and `sync-google-users` takes no `--dry-run`/`--enforce`.
  - It works because the WIF credential files only reach an instance when
    `enable_google_directory_revocation` is true, so their presence (already checked
    by the wrapper) *is* the enable signal. A second flag could only disagree with it.
  - An intermediate design briefly had Terraform write an `openvpn.google_sync_enforce`
    fact; obsolete, dropped with the dry-run.

Exit-status contract the toolkit subcommand MUST honor (the wrapper depends on it):
- `0` ran fine; `78` (EX_CONFIG) Google side not configured yet -> wrapper treats as
  "not ready", logs, exits 0; any other code -> real failure, wrapper exits non-zero
  so cron mails.
- The subcommand takes **no mode flags**; invoked bare as `ih-openvpn sync-google-users`.

Other notes:
- Lock file lives on the **EFS-shared config dir**, not /var/run, so it is
  cluster-wide across the ASG (all instances mount the same PKI; concurrent
  `easyrsa revoke` would race on index.txt).
- Cron minute defaults to `fqdn_rand(60)` so the ASG does not hit the Directory API
  in lockstep.

Verified (re-run after the dry-run removal): `puppet-lint --fail-on-warnings` clean
on all four module paths; ERB renders; `bash -n` clean; and the full gate matrix was
executed **on the live Ubuntu instance i-0bb32c31f4bf8d62f** (sandboxed copy, never
touching the real PKI). Every "not ready" state exits 0 silently; only a genuine
post-deployment failure exits non-zero. Confirmed against the *currently installed*
toolkit (which lacks the subcommand) -> exits 0 gracefully.

Note on facts: `custom_facts` from Terraform land in
`/etc/puppetlabs/facter/facts.d/custom.json` and keep their JSON types (e.g.
`"openvpn_port": 1194` is consumed as a Puppet `Integer`). Not needed by this class
as built, but relevant if a fact is ever added.

## Toolkit side — WRITTEN 2026-07-19

Repo `/Users/aleks/code/infrahouse/infrahouse-toolkit`, clean `main`, uncommitted.

- `infrahouse_toolkit/cli/ih_openvpn/lib.py` (new) — `index_path`, `parse_index`,
  `extract_common_name`, `is_user_certificate`, `valid_user_certificates`,
  `revoke_client`.
- `infrahouse_toolkit/cli/ih_openvpn/cmd_sync_google_users/__init__.py` (new) —
  the subcommand, `GoogleNotConfigured`, `EX_CONFIG = 78`.
- `cmd_revoke` refactored onto `lib.revoke_client`; `cmd_list` onto
  `lib.index_path`.
- `--config-dir` added as a GROUP option (alongside `--easyrsa-path`) into
  `ctx.obj`, consumed by all three subcommands. `revoke_client` takes it as a
  required argument -- deliberately no default, so no caller can silently act on
  `/etc/openvpn` while the operator pointed the group elsewhere.
- `requirements.txt`: added `google-auth ~= 2.0`, `google-api-python-client ~= 2.0`.

**Safety: the server certificate must never be revocable.** The live PKI's only
entry is `V ... /CN=server` -- the OpenVPN server's own cert. A naive
"valid CNs minus active Google users" diff computes `{server}` and revokes it,
killing the VPN, and does so on the FIRST run of a fresh deployment before any
user enrolls. Two independent guards: `is_user_certificate()` requires an `@` in
the CN (portal-minted user CNs are Google emails; `server` has none), and an
empty directory response is refused outright rather than treated as "everyone was
deactivated". Tests: `test_valid_user_certificates_excludes_server`,
`test_never_revokes_the_server_certificate`.

Verified: pylint 9.95/10 on the module, black + isort clean, full suite
297 passed / 4 skipped, and the rendered Puppet wrapper driving the real
installed CLI exits 78 cleanly with no traceback.

## Open item for the toolkit work

`cmd_revoke` uses `EASYRSA_PASSIN=file:/etc/openvpn/ca_passphrase`, but
`templates/openvpn_server/regenerate-crl.sh.erb` documents that `file:` fails with
OpenSSL 3.x in easy-rsa batch mode (OpenVPN/easy-rsa#692) and deliberately uses
`pass:$(cat ...)` instead. A direct openssl probe on the instance (3.0.13) showed
raw `file:` and `pass:` BOTH work, so the failure is in easy-rsa's batch handling,
not the openssl BIO — NOT reproduced and NOT cleared. Check this before relying on
`cmd_revoke_client` in the sync path, or the feature may compute a correct diff and
then silently fail to revoke.

## Housekeeping / risks to raise with the user

- **All the terraform work is uncommitted on `main`** — `google-wif.tf`,
  `scripts/`, `templates/`, `tests/`, `spikes/`, plus modified `asg.tf`,
  `terraform.tf`, `Makefile`, `README.md`, `docs/getting-started.md`,
  `requirements.txt`, `.bumpversion.cfg`. Nothing is on a branch. Needs a branch
  + PR before it can land.
- **`test_data/google_wif/` has a live applied stack** (~730KB tfstate): full
  OpenVPN ASG + NLB + EFS + Route53 + the GCP WIF resources, running in
  us-west-2 and billing. Instance `i-0bb32c31f4bf8d62f` launched 2026-07-19
  20:02 UTC. Ask before destroying — it is the verification rig, and tearing it
  down forfeits the ability to test the Puppet side against a real WIF instance.