#!/bin/bash
#
# Managed by Puppet (profile::hashicorp_repo). Do not edit locally.
#
# Converge an APT keyring from the signing key a vendor publishes at a URL, so
# long-lived instances pick up a rotated key without being reprovisioned. Trust
# is anchored on the TLS channel to that URL (no fingerprint pinning): a vendor
# that rotates with no overlap and no cross-signature leaves no pinned key able
# to vouch for the new one.
#
# Usage:
#   converge-apt-keyring.sh check <url> <keyring>
#       exit 0 if <keyring> already matches the key published at <url>,
#       exit 1 otherwise (including when the key cannot be fetched, so the
#       caller runs 'apply' and surfaces the problem).
#   converge-apt-keyring.sh apply <url> <keyring>
#       fetch + dearmor + install the keyring and print its fingerprint(s).
#       If the fetch fails while a keyring is already installed, warn and keep
#       it (exit 0): the caller runs before 'apt-get update', so failing here
#       would skip the whole Puppet run over a vendor outage the installed key
#       may well survive. With no keyring installed, fail.
#
set -euo pipefail

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

usage() {
  echo "usage: $0 {check|apply} <url> <keyring>" >&2
  exit 2
}

[ "$#" -eq 3 ] || usage
action=$1
url=$2
keyring=$3

# A throwaway GnuPG home: Puppet's exec may run without HOME, and nothing here
# should touch root's keyrings.
gnupghome=$(mktemp -d)
candidate=$(mktemp)
trap 'rm -rf "${gnupghome}" "${candidate}"' EXIT

# Print the primary key fingerprint(s) in keyring $1, one per line.
fingerprints() {
  gpg --homedir "${gnupghome}" --batch --quiet --show-keys --with-colons "$1" \
    | awk -F: '$1 == "pub" { want = 1 } $1 == "fpr" && want { print $10; want = 0 }'
}

# Fetch the armored key over HTTPS and dearmor it into $1. Callers test the
# result, which turns off errexit in here -- hence the explicit returns.
fetch_dearmored() {
  local out=$1 armored
  armored=$(mktemp) || return 1
  # shellcheck disable=SC2064
  trap "rm -f '${armored}'" RETURN
  curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --retry 3 --retry-delay 2 --max-time 30 \
    --output "${armored}" "${url}" || return 1
  gpg --dearmor <"${armored}" >"${out}" || return 1
  # Refuse an empty result or anything that does not parse as a public key.
  [ -n "$(fingerprints "${out}")" ]
}

case "${action}" in
  check)
    fetch_dearmored "${candidate}" || exit 1
    # 0 = already converged, 1 = differs or keyring missing (cmp says 2).
    cmp -s "${candidate}" "${keyring}" || exit 1
    ;;
  apply)
    if ! fetch_dearmored "${candidate}"; then
      if [ -s "${keyring}" ]; then
        echo "WARNING: could not fetch ${url}; keeping the installed ${keyring}" >&2
        exit 0
      fi
      echo "ERROR: could not fetch ${url} and no keyring is installed at ${keyring}" >&2
      exit 1
    fi
    if cmp -s "${candidate}" "${keyring}"; then
      exit 0
    fi
    install -D -m 0644 "${candidate}" "${keyring}"
    echo "Installed ${keyring} from ${url}, fingerprint(s):"
    fingerprints "${keyring}"
    ;;
  *)
    usage
    ;;
esac
