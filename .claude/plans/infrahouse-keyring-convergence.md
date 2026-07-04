# InfraHouse APT Keyring Convergence

Manage `/etc/apt/keyrings/infrahouse.gpg` from Puppet so **already-running** instances pick up
rotated GPG signing keys. This is the client-side "long pole" of the InfraHouse APT GPG key
rotation (noble signing key expires **2026-07-20**).

## Why

Today cloud-init installs the keyring **only at first boot** (`bootcmd.sh`, guarded by
`if ! test -f $REPO_LIST`). `profile::repos` sets up the `apt` module but **does not** manage the
InfraHouse keyring. So a long-lived instance that isn't reprovisioned never receives a new key —
when the current signing key expires, `apt-get update` fails fleet-wide with `EXPKEYSIG`.

Puppet runs every cycle (`apt` update frequency is already `always`), so it's the right place to
**converge** the keyring: fetch the published (possibly multi-key) bundle each run and rewrite the
keyring idempotently. Rotation then needs no per-key Puppet change — new keys just appear in the
bundle.

## Design

Mirror cloud-init 2.4.0's approach (it dropped fingerprint pinning; trust is anchored on **TLS**
to `release-<codename>.infrahouse.com`):

- Fetch `https://release-${codename}.infrahouse.com/DEB-GPG-KEY-release-${codename}.infrahouse.com`
  each run.
- `gpg --dearmor` → `/etc/apt/keyrings/infrahouse.gpg` (handles concatenated multi-key bundles).
- Write idempotently (only rewrite when content changes); `notify` an `apt-get update`.
- **No fingerprint pin** — stay consistent with cloud-init; trust is the TLS channel to our own
  repo host. (If we ever want defense-in-depth, pin the *set* of fingerprints, but do it in both
  places or neither.)
- Only manage the keyring for codenames the node actually uses (derive from `$facts['os']` /
  `lsb` codename); don't assume noble.

Likely shape: a new `profile::infrahouse_repo` class (or extend `profile::repos`) using an
`exec`/`file` pair, or `apt::keyring` if the module version supports fetching. Keep the sources
list ownership consistent with what cloud-init writes (`/etc/apt/sources.list.d/50-infrahouse.list`)
so the two don't fight.

## Progress Tracker

### Prerequisites (done elsewhere)
- [x] Repo module publishes a multi-key bundle — `terraform-aws-debian-repo` 4.0.0 (`gpg_public_keys`)
- [x] cloud-init consumes the bundle over TLS — `terraform-aws-cloud-init` 2.4.0
- [x] Package-neutral re-sign tool — `ih-s3-reprepro export` (infrahouse-toolkit #249)

### Phase 0: Implement
Implemented in `environments/development/modules/profile` (dev-first; promotes to sandbox then
global). New class `profile::infrahouse_repo` (wired into `profile::base`) + deployed script
`files/converge-infrahouse-keyring.sh`. Class converges **both** the signing key and the repo
source line — they're one concern.
- [x] Add convergence class: keyring (fetch bundle → dearmor → `/etc/apt/keyrings/infrahouse.gpg`)
  **and** source list (`/etc/apt/sources.list.d/50-infrahouse.list`).
- [x] Idempotent; codename derived from facts (`os.distro.codename`, overridable param) and fills
  both host (`release-<codename>`) and suite. Keyring `exec` guarded by a `check` verb; source list
  is a native `file`. Both notify a single shared refreshonly `apt-get update`, so steady state is a
  no-op and apt only refreshes on an actual change.
- [x] Shared ownership with cloud-init is **intentional**, not a conflict: cloud-init must seed both
  at first boot (ih-secrets has to be installable before Puppet runs — secret *names* live in
  user-data, values don't). Puppet renders the source line **byte-identical** to cloud-init's seed
  so the two never fight; Puppet just keeps it converged afterward. (So: no follow-up to remove the
  cloud-init write — the seed is load-bearing.)
- [x] Fetch failure leaves prior keyring intact (atomic write to temp, install only on success).
- [~] ~~Unit/rspec-puppet coverage~~ — skipped: repo has no existing class specs / test harness
  provisioned. Gates used instead: `puppet-lint --fail-on-warnings` (pass), `shellcheck` (pass),
  real-node validation on `jumphost-sincere-crawdad` (Phase 1).

### Phase 1: Development
Test node: `jumphost-sincere-crawdad.rmdbkn.ci-cd.infrahouse.com`
(`/etc/puppetlabs/facter/facts.d/puppet.yaml` → `puppet_environment: development`, `puppet_role: jumphost`).

**1a. Real-time apply (uncommitted code, iterate live)** — done 2026-07-04 on the test node.
- [x] Sync the working `environments/development/modules/profile` to the node and `ih-puppet apply`
- [x] `50-infrahouse.list` unchanged vs cloud-init's seed — md5 `627951c5b24fde2de0feb9e93700c0b6`
  before **and** after (byte-identical → no rewrite/churn)
- [x] `apt-get update` clean against the InfraHouse repo (`Hit … noble InRelease`, no `EXPKEYSIG`)
- [x] Second run is a clean no-op (guarded `exec` skips; no spurious `apt-get update`)
- [x] Keyring == published bundle verified (`curl … | gpg --dearmor | cmp` matches)
- [x] **Rewrite path** exercised: staled the keyring (`truncate -s 0`), re-applied →
  `Exec[…::converge]` ran, `Exec[…::apt_update]` triggered once, `cmp` vs backup byte-identical.
  Second pass no-op. This also covers the drifted first-boot-only node (same divergence → rewrite).
  Genuine *new-key* pickup still awaits the upstream bundle rotation (see Finding).

> **Finding (2026-07-04):** the live `release-noble` bundle is still **single-key** — only the old
> signing key `A627B776…689AD619` (`[expires: 2026-07-20]`). The **new rotated key is not published
> yet**. So end-to-end multi-key convergence can't be validated here until upstream adds the new key
> to `gpg_public_keys` and re-exports. Deploying this class is **necessary but not sufficient** for
> the rotation: someone must also publish the new key into the live bundle (dual-key) — see Deadline
> note. `gpg --show-keys` "lists every key in the bundle" check deferred until then.

**1b. Cut a release** (once the live test looks good)
- [x] Merge to `main` → CD publishes the `.deb` to the APT repo (dev picks it up on next Puppet run)
  — PR [#278](https://github.com/infrahouse/puppet-code/pull/278) **merged**.

**1c. Zero-bootstrap check via instance-refresh** — done 2026-07-04 on fresh instance `ip-10-1-100-168`.
- [x] Brand-new instance provisioned from scratch off the released `.deb`
- [x] cloud-init first-boot + Puppet convergence agree: script deployed, `Exec[…::converge]` no-op
  (keyring already == bundle), source list byte-identical (no rewrite), no spurious apt refresh
- [x] `keyring == published bundle` (`curl … | cmp` → converged), `apt-get update` clean
  (`Hit … noble InRelease`, no `EXPKEYSIG`) — Puppet bootstraps an instance from zero

### Phase 2: Sandbox
- [x] Promote: copy the change into `environments/sandbox/modules/profile` (byte-identical to dev:
  `infrahouse_repo.pp` + `files/converge-infrahouse-keyring.sh` + `base.pp` include).
- [x] Cut a release — PR [#279](https://github.com/infrahouse/puppet-code/pull/279) **merged** → CD.
- [x] Watch sandbox nodes across roles: keyring converges, `apt-get update` clean, no drift.
  Verified 2026-07-04 via SSM: `elastic_master` (`i-0f554096e62f32ea0`) `puppet_exit=0` +
  `CONVERGED_OK` (regression below fixed), and `jumphost` (`i-04c4cd399cd73d6a0`) `puppet_exit=0` +
  `CONVERGED_OK` + apt `Hit … noble InRelease`. Source list md5 `627951c5…` on both.
  - **Regression found on `elastic_master` (sandbox `ip-10-0-2-191`):** `profile::infrahouse_repo`
    is in `base` (every node) and `ensure_packages`'d `ca-certificates`, which collided with
    `profile::elastic::tls`'s **native** `package { 'ca-certificates' }` → duplicate declaration,
    catalog failed. Fix: `base`/`infrahouse_repo` now **owns** `ca-certificates` (it's a fleet-wide
    TLS need); removed the native block from `elastic::tls`, which just `require`s it. Dev never hit
    it (only jumphost was tested). Applied to dev + sandbox; global gets it with the Phase-3 promo.

### Phase 3: Production (global modules)
- [x] Promote: move the change into global `modules/profile` (production has no env-local override).
  Bundled with the `elastic::tls` ca-certificates fix so prod's elastic nodes never see the broken
  intermediate state; all 4 touched files now byte-identical across global/dev/sandbox (invariant
  from #276 restored). PR pending.
- [ ] Cut a release (merge → CD); deploy fleet-wide
- [ ] Watch production; spot-check long-lived instances across services (openvpn, jumphost, etc.)
- [ ] **GATE:** fleet trusts the current bundle before any signing-key retire happens upstream

## Deadline note

This gates the upstream rotation: `terraform-aws-debian-repo` cannot switch signing to the new key
(dual-sign → retire old) until running instances trust it (the GATE above), and that must complete
**before 2026-07-20**. If Phases 1–3 can't be deployed and verified with margin, a **one-off fleet
keyring refresh** (SSM run-command / ansible) is the deadline fallback, with this convergence class
as the durable follow-up.

## Cross-references
- Full rotation design/runbook: `terraform-aws-debian-repo/.claude/plans/gpg-key-rotation-design.local.md`
- cloud-init client behavior: `terraform-aws-cloud-init/files/bootcmd.sh`, issue infrahouse/terraform-aws-cloud-init#89
