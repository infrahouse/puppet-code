# Plan: auto-revoke OpenVPN certs for deactivated Google users

This is the **Puppet side** of a two-repo feature. The companion Terraform
work (new service-account secret + IAM) lives in
`terraform-aws-openvpn`, and there is one small optional change to the
OpenVPN portal app (also in that repo).

## Why

Client certificates are minted by the **OpenVPN portal** (Flask app,
`terraform-aws-openvpn/portal/portal/__init__.py`). On Google OAuth login
the portal calls `ensure_certificate(config_dir, email)` →
`generate_client_key()`, which runs:

```
easyrsa gen-req  <email> nopass      # EASYRSA_REQ_CN = email
easyrsa sign-req client <email>      # EASYRSA_PASSIN = file:<dir>/ca_passphrase
```

So the certificate's **CN is literally the user's Google email**, and the
PKI lives on the shared EFS volume at
`<config_dir>/pki/{issued/<email>.crt, private/<email>.key}`.

When a user is suspended or deleted in Google Workspace, the portal's
`authorize_email()` stops them from logging in — so they can no longer
*mint* a new cert. But the `.ovpn` profile they already downloaded (cert +
private key) keeps working until the CA **revokes** it. Nothing revokes it
today. This feature closes that window.

## Identity binding already exists (no mapping layer needed)

Because CN == email, reconciliation is a pure set-diff:

```
{ valid CNs in pki/index.txt }  −  { currently-active Google users }  =  certs to revoke
```

- **Issued-cert source of truth**: `<config_dir>/pki/index.txt`.
  `V` lines = valid, `R` = already revoked; the CN is on each line.
- **Revocation primitive** (already used by the monthly CRL cron in
  `profile::openvpn_server::config`, `config.pp:178`):
  `easyrsa revoke <email>` then `easyrsa gen-crl`, signed with
  `EASYRSA_PASSIN=file:<config_dir>/ca_passphrase` (the passphrase file is
  already present at mode 0400). OpenVPN re-reads the CRL on every new
  connection — no service restart needed (README.erb:49).

The single set-diff catches suspended, deleted, **and** domain-removed
users in one pass.

## The one net-new credential (Terraform side)

The portal's existing `google_client` secret is an **OAuth web client** —
only good for interactive user login, not for querying account status.
Determining "is this user suspended?" requires the **Admin SDK Directory
API**, which needs a **service account with domain-wide delegation**,
scope `admin.directory.user.readonly`, impersonating a Workspace admin.

In `terraform-aws-openvpn`:
- Add an AWS Secrets Manager secret holding the SA JSON — mirror the
  existing `google_client` module in `secrets.tf`.
- Grant the instance role `secretsmanager:GetSecretValue` on it, alongside
  `ca_key_passphrase_secret` (`asg.tf:32`, `iam.tf`).
- Surface the secret name to the instance as a custom fact (same channel
  `openvpn.ca_key_passphrase_secret` uses), so Puppet can read it.

## Puppet side (this repo)

New class `profile::openvpn_server::google_revocation_sync`, included from
`profile::openvpn_server` (`openvpn_server.pp:39-41`, next to `nat`,
`auditd`, `cloudwatch_agent`). It deploys:

1. **A Python sync script** (Python because it needs
   `google-api-python-client` + `boto3` — the same stack the portal
   already runs). Logic:
   - Fetch the SA JSON from Secrets Manager → build a Directory API client
     (delegated to an admin user).
   - List **active** users across the portal's `allowed_domains`
     (`users.list`, paginated, filtering out `suspended`) → build the
     allow-set of emails.
   - Parse `pki/index.txt` for `V` entries → valid CNs, **excluding** the
     `server` cert and the CA CN.
   - Diff → for each CN not in the allow-set: `easyrsa revoke <cn>`; then
     run `easyrsa gen-crl` **once** after the loop.
   - Log to syslog (tag `openvpn-google-sync`, auth facility — matching the
     CRL cron's convention) and mail `$mailto` a summary of revocations.

2. **A daily cron**, sibling to the existing monthly
   `regenerate_openvpn_crl` (`config.pp:210`), with `MAILTO=${mailto}`.

## Safety rails (the important part)

- **Concurrency lock — the real risk.** The portal issues certs (mutating
  `index.txt`/`pki`) at the same time this cron revokes. Two concurrent
  `easyrsa` processes on the shared EFS PKI can corrupt `index.txt`. Wrap
  the cron script — and ideally the portal's `generate_client_key()` — in
  `flock` on a shared lockfile under `<config_dir>`.
- **Zero / low-count abort.** If the Directory API returns an empty or
  implausibly small active-user list (API hiccup, expired delegation),
  abort **without revoking anything**. Optionally cap: refuse a run that
  would revoke more than N% of valid certs.
- **Dry-run mode.** A flag that logs intended revocations without touching
  the PKI. Run it that way first in dev/sandbox.
- **Idempotent.** Skip CNs already marked `R` in `index.txt`.
- **Scope guard.** Only ever revoke CNs whose domain is in
  `allowed_domains`; never touch anything else on the PKI.

## Open decision

Revoke **immediately** on suspension, or after a grace period? Immediate is
the secure default; a grace window avoids cutting access during a brief HR
suspension. Cheap to add later as a Hiera-configurable knob
(`profile::openvpn_server::revocation_grace_days`, default 0).

## Rollout

1. Terraform: add SA secret + IAM + delegation; publish the secret-name
   fact. (`terraform-aws-openvpn`)
2. Puppet: land the profile in `environments/development` first, run with
   `--dry-run`, verify the diff against `index.txt` looks right.
3. Add the `flock` lock to the portal's issuance path.
4. Promote development → sandbox → production (the repo's normal per-env
   promotion flow).