# Task: Multi-Workspace directory revocation — puppet-code

## Why

The OpenVPN Google-directory revocation cron runs `ih-openvpn sync-google-users`,
which revokes VPN certs for deactivated Workspace users. It's being extended to
cover **multiple, separate Google Workspace tenants** (real case: `acme.io`
and `acme.dev`). This is a three-repo change; **puppet's part is the
smallest** — the wrapper just needs to accept the new plural env var. The
per-Workspace looping happens entirely inside the toolkit; there is **no cron
multiplexing** and no per-Workspace resources here.

Companion briefs:
- **infrahouse-toolkit:** `ih-openvpn sync-google-users` loops over subjects,
  unions, all-or-nothing (the real logic).
- **terraform-aws-openvpn:** writes the plural admin-subject var into `wif.env`.

## Cross-repo contract (must match the other two briefs verbatim)

`/opt/openvpn-wif/wif.env` (written by terraform, sourced by *this* wrapper before
invoking the tool) gains a plural var and keeps the singular for back-compat:

```sh
export GOOGLE_APPLICATION_CREDENTIALS=/opt/openvpn-wif/google-wif.json
export WIF_SA_EMAIL=openvpn-dir-reader@PROJECT.iam.gserviceaccount.com  # one SA & GCP project, shared by all Workspaces
export WIF_ADMIN_SUBJECT=admin@acme.io                             # DEPRECATED: first element, back-compat
export WIF_ADMIN_SUBJECTS=admin@acme.io,admin@acme.dev   # NEW: authoritative, comma-separated
```

The wrapper does not need to parse the list — it only sources `wif.env` and runs
`ih-openvpn`; the toolkit reads `WIF_ADMIN_SUBJECTS` itself. The **only** change
here is the required-var precheck, which currently hard-requires the singular
`WIF_ADMIN_SUBJECT` and would wrongly fail if a future `wif.env` ever emitted only
the plural.

## Current state (file:line — canonical `modules/profile/`; identical copies in
`environments/{development,sandbox}/modules/profile/` and the `debian/` build)

- `modules/profile/manifests/openvpn_server.pp:45-49` — compile-time gate on the
  Terraform-emitted structured fact:
  ```puppet
  if $facts.dig('openvpn', 'google_directory_revocation') {
    class { 'profile::openvpn_server::google_revocation_sync': ... }
  }
  ```
  **No change** — the fact stays a boolean enable-signal; the Workspace count
  lives in `wif.env`, not the fact.
- `modules/profile/manifests/openvpn_server/google_revocation_sync.pp:93-100` —
  single cron `openvpn_google_user_sync`, root, daily, running `$sync_script`.
  **No change** — one cron, the toolkit handles all Workspaces internally.
- `modules/profile/templates/openvpn_server/google-user-sync.sh.erb` — the
  wrapper. Sources `wif.env` (~line 81-89) and enforces required vars:
  ```bash
  for required_var in GOOGLE_APPLICATION_CREDENTIALS WIF_SA_EMAIL WIF_ADMIN_SUBJECT; do
      [ -n "${!required_var:-}" ] || misconfigured "$required_var is not set in $WIF_ENV_FILE"
  done
  ```
  Then runs `"$IH_OPENVPN" --config-dir "$CONFIG_DIR" sync-google-users` (~line 116).
- Toolkit install: `profile::infrahouse_toolkit` → `package { 'infrahouse-toolkit': ensure => latest }`. No version pin; the wrapper probes for the subcommand
  (`ih-openvpn sync-google-users --help`) rather than pinning. `ensure => latest`
  means nodes pick up the new toolkit (≥ 2.62.0) automatically.

## Changes to make

### 1. Wrapper precheck: require "at least one admin subject" (either var)
In `google-user-sync.sh.erb`, change the required-var loop so it no longer hard-
requires the singular. Require the always-present vars unconditionally, then
require **at least one** of `WIF_ADMIN_SUBJECTS` / `WIF_ADMIN_SUBJECT`:

```bash
for required_var in GOOGLE_APPLICATION_CREDENTIALS WIF_SA_EMAIL; do
    [ -n "${!required_var:-}" ] || misconfigured "$required_var is not set in $WIF_ENV_FILE"
done
[ -n "${WIF_ADMIN_SUBJECTS:-}" ] || [ -n "${WIF_ADMIN_SUBJECT:-}" ] \
    || misconfigured "neither WIF_ADMIN_SUBJECTS nor WIF_ADMIN_SUBJECT is set in $WIF_ENV_FILE"
```

That's the whole functional change. The invocation line is unchanged (the toolkit
reads the env itself). Everything else — `flock` EFS lock, `index.txt` not-ready
→ quiet `exit 0`, exit-78 → `misconfigured`/exit 1 so cron mails it, other
non-zero → real failure — stays as-is.

### 2. Apply the edit to all in-repo copies
The file exists identically in:
- `modules/profile/templates/openvpn_server/google-user-sync.sh.erb` (canonical)
- `environments/development/modules/profile/templates/openvpn_server/google-user-sync.sh.erb`
- `environments/sandbox/modules/profile/templates/openvpn_server/google-user-sync.sh.erb`

Keep them byte-identical (that's the repo convention). The `debian/puppet-code/...`
copy is a build artifact — do not hand-edit; it regenerates.

### 3. (Optional) subcommand-capability note
The wrapper already probes `sync-google-users --help`, which covers the *presence*
of the subcommand but not the *plural* capability. Since the module emits BOTH
`WIF_ADMIN_SUBJECT` and `WIF_ADMIN_SUBJECTS`, an un-upgraded toolkit degrades
gracefully (reads the singular, covers the first tenant only) rather than
breaking, so no hard version probe is required. Rely on `ensure => latest` +
release ordering. Do **not** add a brittle version-string parse.

## Testing / acceptance
- `puppet parser validate` / your usual lint on the changed manifests/templates.
- Render/desk-check the wrapper with each of: only `WIF_ADMIN_SUBJECT` set (old
  `wif.env`) → passes precheck; only `WIF_ADMIN_SUBJECTS` set → passes; neither →
  `misconfigured`. If the repo has spec/rspec-puppet coverage for this class,
  extend it; otherwise a shellcheck + manual trace of the precheck is sufficient.
- Confirm no change to the cron resource, the gate, or the fact handling.

## Rollout order (all three repos)
1. **infrahouse-toolkit** ships first (≥ 2.62.0; `ensure => latest` pulls it).
2. terraform-aws-openvpn emits `WIF_ADMIN_SUBJECTS` into `wif.env`.
3. **this repo** — wrapper accepts either var. Safe to land any time after (or
   with) step 2, since the module keeps emitting `WIF_ADMIN_SUBJECT` too, so the
   current wrapper keeps working throughout the transition.

Per the standing rule: this feature is currently dev-env-focused; follow the
existing enablement path (Terraform `google_directory_revocation` fact per node),
not a new hiera key.
