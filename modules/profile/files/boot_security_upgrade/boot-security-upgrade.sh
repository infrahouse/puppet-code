#!/bin/bash
#
# Apply pending security upgrades once, now, with a hard cumulative time bound --
# then let AWS Inspector scan the host.
#
# WHY THIS EXISTS
# unattended-upgrades is what actually patches these hosts, but it runs on a
# timer. Between an instance coming up and that timer firing there is a window in
# which Inspector scans an unpatched host and opens a finding. The finding does
# close on the next unattended-upgrades run -- but by then it has already
# REOPENED its vulnerability group, and a group old enough to be reopened that
# way breaks the remediation SLA. So the fix is not "patch more often on a
# timer", it is "do not present an unpatched host to Inspector at all": patch
# during provisioning, before the instance becomes scannable.
#
# THE EXCLUSION TAG
# Instances are expected to launch carrying the InspectorEc2Exclusion tag (see
# --exclusion-tag), which keeps Inspector from scanning them. This script removes
# that tag once it is done, so the first scan sees an already-patched host and
# the window above never exists.
#
# Removing it is BEST EFFORT and never fails the run. It needs two things that
# are not in place fleet-wide yet: ec2:DeleteTags on the instance profile, and
# the launch-time tag from Terraform. A host that has neither is no worse off
# than it was before this script existed -- it just keeps getting scanned on
# Inspector's own schedule, exactly as today. delete-tags is also idempotent, so
# removing a tag the instance never carried is a no-op.
#
# The tag is dropped whether or not the upgrade SUCCEEDED. Leaving it on a host
# that failed to patch would hide a genuinely vulnerable instance from Inspector,
# which is the opposite of the point.
#
# WHY A SCRIPT INSTEAD OF exec's tries/try_sleep
# Puppet's `timeout` is PER-ATTEMPT, so `tries` multiplies the worst case to
# tries * timeout + (tries-1) * try_sleep with no cumulative cap. That matters
# where a failure is not merely slow: under ih-bootstrap, ih-puppet applies with
# --detailed-exitcodes and exits 4/6 when a resource fails, which trips
# `trap _ih_signal_abandon ERR` and ABANDONs the instance. A retry budget that
# can outlast the bootstrap lifecycle hook is a fleet-churn bug, not a latency
# bug. Bounding total wall clock here lets one legitimately long upgrade use the
# whole window while still capping the worst case.
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
# Usage: boot-security-upgrade.sh [--budget SECONDS] [--marker PATH]
#                                 [--exclusion-tag KEY | --no-exclusion-tag]

# Deliberately no `set -e`: failures of the apt commands are expected and handled
# by the retry loop below.
set -uo pipefail

readonly PROG="boot-security-upgrade"

# Seconds to wait between attempts. Long enough to let a competing dpkg run get
# somewhere, short enough that a 480s budget still affords a couple of dozen
# tries.
readonly RETRY_INTERVAL=15

BUDGET=480
MARKER=/run/boot-security-upgrade.done
EXCLUSION_TAG=InspectorEc2Exclusion

log() { echo "${PROG}: $*"; }
warn() { echo "${PROG}: $*" >&2; }

usage() {
    cat >&2 <<EOF
Usage: ${PROG}.sh [--budget SECONDS] [--marker PATH]
                  [--exclusion-tag KEY | --no-exclusion-tag]
EOF
}

need_value() {
    [ -n "$2" ] || { warn "$1 requires a value"; usage; exit 2; }
}

while [ $# -gt 0 ]; do
    case "$1" in
        --budget)
            need_value "$1" "${2:-}"
            BUDGET="$2"
            shift 2
            ;;
        --marker)
            need_value "$1" "${2:-}"
            MARKER="$2"
            shift 2
            ;;
        --exclusion-tag)
            need_value "$1" "${2:-}"
            EXCLUSION_TAG="$2"
            shift 2
            ;;
        --no-exclusion-tag)
            EXCLUSION_TAG=""
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            warn "unknown argument: $1"
            usage
            exit 2
            ;;
    esac
done

# Returns 0 once the host is patched, 1 if the budget ran out first. The caller
# decides what a 1 means -- see profile::boot_security_upgrade::fail_on_error.
apply_security_upgrades() {
    local deadline attempt remaining

    deadline=$(( $(date +%s) + BUDGET ))
    attempt=0

    while :; do
        remaining=$(( deadline - $(date +%s) ))

        if [ "$remaining" -le 0 ]; then
            warn "${BUDGET}s budget exhausted after ${attempt} attempt(s)"
            return 1
        fi

        attempt=$(( attempt + 1 ))
        log "attempt ${attempt}, ${remaining}s of budget left"

        # Each command is capped at the remaining budget so a single slow command
        # cannot overshoot the deadline.
        if timeout "$remaining" apt-get update -qq && timeout "$remaining" unattended-upgrade; then
            # Written only on success, so a failed upgrade simply retries on the
            # next Puppet apply. Lives on tmpfs so it clears on a real boot.
            touch "$MARKER"
            log "succeeded on attempt ${attempt}"
            return 0
        fi

        # Sleep out the remainder rather than hot-looping the tail of the
        # budget: apt failures under lock contention come back in about a
        # second, so a plain "only sleep if a full interval fits" would turn the
        # last seconds into dozens of retries that do nothing but hammer the
        # lock. The loop head reports the give-up once the sleep runs out.
        remaining=$(( deadline - $(date +%s) ))
        if [ "$remaining" -gt 0 ]; then
            sleep "$(( remaining < RETRY_INTERVAL ? remaining : RETRY_INTERVAL ))"
        fi
    done
}

# Always returns 0: see THE EXCLUSION TAG above. Every failure path here leaves
# the host in the pre-existing state -- scanned on Inspector's own schedule --
# so none of them is worth failing a Puppet run over.
drop_exclusion_tag() {
    local instance_id

    [ -n "$EXCLUSION_TAG" ] || return 0

    # ec2metadata (cloud-guest-utils) and aws (awscli) are declared by
    # profile::boot_security_upgrade, and the exec that calls this script orders
    # itself after both, so there is nothing to probe for here. Off an EC2
    # instance ec2metadata just yields nothing, which the guard below covers.
    instance_id=$(ec2metadata --instance-id 2>/dev/null)
    if [ -z "$instance_id" ]; then
        warn "could not read the instance id; leaving ${EXCLUSION_TAG} in place"
        return 0
    fi

    # No --region: the AWS CLI resolves it from instance metadata, the same way
    # the other on-instance scripts in this repo rely on.
    if aws ec2 delete-tags --resources "$instance_id" --tags "Key=${EXCLUSION_TAG}" 2>&1; then
        log "removed ${EXCLUSION_TAG} from ${instance_id}; Inspector may scan now"
    else
        warn "could not remove ${EXCLUSION_TAG} from ${instance_id} (no ec2:DeleteTags?); Inspector keeps its own schedule"
    fi

    return 0
}

apply_security_upgrades
status=$?

drop_exclusion_tag

exit "$status"
