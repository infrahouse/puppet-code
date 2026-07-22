#!/usr/bin/env bash
# gha-restart-when-idle.sh -- managed by Puppet (profile::github_runner::service).
#
# Companion to /etc/needrestart/conf.d/90-actions-runner.conf, which stops
# unattended-upgrades from restarting actions-runner.service mid-job. That keeps
# running jobs alive, but leaves the runner process still mapping the
# pre-upgrade shared libraries. Run periodically by gha-restart-when-idle.timer,
# this restarts the runner so those patched libraries actually get loaded --
# but ONLY when the runner is idle and ONLY when a restart is actually pending.
set -euo pipefail

SERVICE=actions-runner.service

# A job in flight always has a Runner.Worker process; idle never does.
running_a_job() { pgrep -f 'Runner\.Worker' >/dev/null 2>&1; }

# 1. Never touch a runner that is executing a job.
running_a_job && exit 0

# 2. Is a restart actually pending? True when the runner (or a child) still maps
#    a shared library that an upgrade has since replaced on disk -- a "(deleted)"
#    mapping in /proc/PID/maps. This is ground truth, independent of how
#    needrestart chooses to list a service we have told it not to restart.
main_pid=$(systemctl show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)
[ "${main_pid:-0}" -gt 0 ] || exit 0   # not running -> nothing to restart

pending=0
for pid in "$main_pid" \
           $(pgrep -P "$main_pid" 2>/dev/null || true) \
           $(pgrep -f 'Runner\.Listener' 2>/dev/null || true); do
  if grep -qsE '\.so[^ ]* \(deleted\)$' "/proc/${pid}/maps" 2>/dev/null; then
    pending=1
    break
  fi
done
[ "$pending" -eq 1 ] || exit 0

# 3. Re-check idle at the last moment to narrow the small race with a job that
#    may have started since step 1, then restart to load the patched libraries.
running_a_job && exit 0
logger -t gha-restart-when-idle "patched libraries pending and runner idle -> restarting ${SERVICE}"
systemctl restart "$SERVICE"
