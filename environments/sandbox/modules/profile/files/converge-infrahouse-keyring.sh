#!/bin/bash
#
# Managed by Puppet (profile::infrahouse_repo). Do not edit locally.
#
# Converge /etc/apt/keyrings/infrahouse.gpg from the published InfraHouse
# signing-key bundle so that long-lived instances pick up rotated GPG keys
# without being reprovisioned. Trust is anchored on the TLS channel to
# release-<codename>.infrahouse.com (no fingerprint pinning), consistent with
# cloud-init. The (possibly concatenated multi-key) armored bundle is fetched
# each run and dearmored into the keyring.
#
# Usage:
#   converge-infrahouse-keyring.sh check <codename>
#       exit 0 if the installed keyring already matches the published bundle,
#       exit 1 otherwise (including when the bundle cannot be fetched, so the
#       caller re-runs 'apply' and surfaces the underlying error).
#   converge-infrahouse-keyring.sh apply <codename>
#       fetch + dearmor + install the keyring atomically. A fetch/dearmor
#       failure leaves the existing keyring intact. Refreshing apt is left to
#       the Puppet-managed 'apt-get update' that this exec notifies.
#
set -euo pipefail

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

KEYRING=/etc/apt/keyrings/infrahouse.gpg

usage() {
  echo "usage: $0 {check|apply} <codename>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
action=$1
codename=$2
url="https://release-${codename}.infrahouse.com/DEB-GPG-KEY-release-${codename}.infrahouse.com"

# Fetch the armored bundle over TLS and dearmor it into $1. Returns non-zero
# without touching $KEYRING on any failure (fetch, dearmor, or empty result).
fetch_dearmored() {
  local out=$1 armored
  armored=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '${armored}'" RETURN
  curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 2 --max-time 30 \
    --output "${armored}" "${url}"
  gpg --dearmor <"${armored}" >"${out}"
  # Refuse to install an empty/garbage keyring.
  test -s "${out}"
}

candidate=$(mktemp)
trap 'rm -f "${candidate}"' EXIT

case "${action}" in
  check)
    fetch_dearmored "${candidate}" || exit 1
    # 0 = already converged, 1 = differs or keyring missing.
    cmp -s "${candidate}" "${KEYRING}"
    ;;
  apply)
    fetch_dearmored "${candidate}"
    if cmp -s "${candidate}" "${KEYRING}"; then
      exit 0
    fi
    install -D -o root -g root -m 0644 "${candidate}" "${KEYRING}"
    ;;
  *)
    usage
    ;;
esac