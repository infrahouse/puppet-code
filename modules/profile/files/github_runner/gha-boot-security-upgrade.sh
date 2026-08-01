#!/bin/bash
#
# One-shot security patching during runner provisioning, with a hard cumulative
# time bound.
#
# Why a script instead of exec's tries/try_sleep: Puppet's `timeout` is
# PER-ATTEMPT, so `tries` multiplies the worst case to
# tries * timeout + (tries-1) * try_sleep with no cumulative cap. That matters
# here because an overrun is not merely a slow run -- ih-puppet applies with
# --detailed-exitcodes and exits 4/6 when a resource fails, which trips
# ih-bootstrap.sh's `trap _ih_signal_abandon ERR` and ABANDONs the instance. So a
# retry budget that can exceed the bootstrap lifecycle hook is a fleet-churn bug,
# not a latency bug. Bounding total wall clock here lets one legitimately long
# upgrade use the whole window while still capping the worst case.
#
# What actually needs retrying: both commands below can fail within seconds under
# lock contention.
#   - `apt-get update` takes /var/lib/apt/lists/lock, which DPkg::Lock::Timeout
#     does NOT cover (measured: fails in ~1s even with the option set).
#   - `unattended-upgrade` refuses to run concurrently with itself.
# Contenders are routine: the Inspector and GuardDuty agents each dpkg-install
# about a minute into every boot, squarely inside the provisioning window.
#
# Note ih-puppet already runs the catalog twice and only checks the second exit
# code, so a transient failure gets one free retry above this script too.
#
# Usage: gha-boot-security-upgrade.sh [budget_seconds] [marker_path]

# Deliberately no `set -e`: failures of the apt commands are expected and handled
# by the retry loop below.
set -uo pipefail

BUDGET="${1:-480}"
MARKER="${2:-/run/gha-boot-upgrade.done}"

deadline=$(( $(date +%s) + BUDGET ))
attempt=0

while :; do
    attempt=$(( attempt + 1 ))
    remaining=$(( deadline - $(date +%s) ))

    if [ "$remaining" -le 0 ]; then
        echo "gha-boot-security-upgrade: ${BUDGET}s budget exhausted after ${attempt} attempt(s)" >&2
        exit 1
    fi

    echo "gha-boot-security-upgrade: attempt ${attempt}, ${remaining}s of budget left"

    # Each command is capped at the remaining budget so a single slow command
    # cannot overshoot the deadline.
    if timeout "$remaining" apt-get update -qq && timeout "$remaining" unattended-upgrade; then
        # Written only on success, so a failed upgrade simply retries on the next
        # Puppet apply. Lives on tmpfs so it clears on a real boot.
        touch "$MARKER"
        echo "gha-boot-security-upgrade: succeeded on attempt ${attempt}"
        exit 0
    fi

    # Only sleep if there will still be budget to use afterwards.
    if [ $(( deadline - $(date +%s) )) -gt 15 ]; then
        sleep 15
    fi
done
