# Plan: actions-runner graceful scale-in (Puppet side)

Tracks:
- https://github.com/infrahouse/terraform-aws-actions-runner/issues/81

This is the **Puppet side** of a two-repo fix. The companion Terraform
work lives in `terraform-aws-actions-runner` (see that repo's
`.claude/plans/warm-pool-protection-race.md`).

## Why

When an AWS ASG picks a self-hosted GitHub Actions runner for scale-in,
AWS sets the instance to `Terminating:Wait` and fires the deregistration
lifecycle hook. Today's deregistration Lambda reacts by issuing an SSM
command to `systemctl stop actions-runner.service`, which takes ~11s to
reach the host. During that window, GitHub can dispatch a queued job to
the runner's open long-poll. The job's `gha_prerun.sh` hook calls
`SetInstanceProtection(true)` on the now-`Terminating:Wait` instance,
AWS rejects it with `ValidationError`, and the job exits 1 before any
user code runs.

We cannot close that window (actions-runner is closed to us; shrinking
the SSM round-trip doesn't eliminate the race). So we accept that a job
*can* land on a `Terminating:Wait` instance and make that path
successful:

1. `gha_prerun.sh` tolerates the state — lets the job proceed.
2. Runner receives SIGTERM via systemd, gracefully finishes the in-flight
   job (including `gha_postrun.sh`), then exits.
3. `ExecStopPost` closes the lifecycle hook. Instance terminates.
4. A heartbeater keeps the hook alive for long-running jobs.

This also fixes three latent systemd bugs that are silently SIGKILL-ing
in-flight jobs today on any clean runner stop (including operator
actions, not just scale-in).

## Research notes shaping this design

From reading the actions-runner source + GitHub docs:

- **SIGTERM is graceful.** `Runner.cs` → `HostContext.ShutdownRunner()`
  → `jobDispatcher.ShutdownAsync()` waits for the in-flight Worker to
  finish, then exits.
- **`runsvc.sh` wraps the runner** with `trap 'kill -INT $PID' TERM INT`.
  Our current `ExecStart` uses `run.sh` directly, which has no trap.
- **GitHub's recommended systemd unit** sets `KillMode=process`,
  `KillSignal=SIGTERM`, and `TimeoutStopSec=5min`. Our current unit
  omits the first two (so cgroup SIGKILL at 90s kills in-flight jobs)
  and uses systemd's 90s default for the third.

## What Terraform will provide (dependency)

The `terraform-aws-actions-runner` module (Part 1 of the overall plan)
will:

1. Inject a new Puppet custom fact `deregistration_hookname` — the
   name of the lifecycle hook we need to complete/heartbeat. Injected
   via cloud-init external facts, same mechanism as the existing
   `registration_token_secret_prefix` fact.
2. Set `heartbeat_timeout = 1800` (30min) on the deregistration
   lifecycle hook.
3. Add `autoscaling:CompleteLifecycleAction`,
   `autoscaling:RecordLifecycleActionHeartbeat`, and
   `secretsmanager:DeleteSecret` to the instance profile.
4. Simplify the deregistration Lambda to fire-and-forget — it sends
   the SSM stop command and exits; this Puppet-side machinery
   completes the lifecycle hook.

All four land in a subsequent `terraform-aws-actions-runner` release.
Puppet changes here must be **deployed first** and must **remain safe
on old-Terraform ASGs** that don't have any of the above (see
Backwards compatibility).

---

# Changes

**All development happens under `environments/development/modules/profile/github_runner/` only.**
Do not touch `environments/sandbox/` or the top-level `modules/`
(global) during implementation. Promotion sequence is in §9.

## 1. Fix the systemd unit

Edit `environments/development/modules/profile/templates/github_runner/actions-runner.service.erb`
to match GitHub's recommended configuration, plus our lifecycle hook:

```
[Unit]
Description=GitHub self-hosted runner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=<%= @start_script %>
ExecStopPost=/usr/local/bin/gha-on-runner-exit.sh
Environment=DEREGISTRATION_HOOK_NAME=<%= @deregistration_hookname %>
WorkingDirectory=<%= @runner_package_directory %>
User=<%= @github_runner_user %>
Group=<%= @github_runner_group %>
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=21600
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`@deregistration_hookname` is read from `$facts['deregistration_hookname']`
in `service.pp`, with an empty-string fallback if the fact is missing
(back-compat with old-Terraform ASGs).

Three real fixes + one new hook + one environment variable:
- `KillMode=process` (was default `control-group`, which SIGKILLed the
  runner's Worker process and killed jobs mid-flight).
- `TimeoutStopSec=21600` (6h — covers any realistic Terraform apply or
  long-running job; was default 90s).
- `KillSignal=SIGTERM` — explicit, matches GitHub's template.
- `ExecStopPost=/usr/local/bin/gha-on-runner-exit.sh` — see §3.
- `Environment=DEREGISTRATION_HOOK_NAME=...` — consumed by the
  ExecStopPost script.

## 2. Make `start-actions-runner.sh.erb` signal-transparent

Replace the final `exec ./run.sh` with `exec ./bin/runsvc.sh`. The runner
tarball ships both (`runsvc.sh` lives under `bin/`); `runsvc.sh` handles
signal propagation correctly
(`trap 'kill -INT $PID' TERM INT`). Final shape:

```bash
#!/usr/bin/env bash
set -eu

instance_id=$(ec2metadata --instance-id)

while true; do
  state=$(aws autoscaling describe-auto-scaling-instances \
          --instance-ids "$instance_id" \
          --query 'AutoScalingInstances[0].LifecycleState' --output text)
  [[ "$state" == "InService" ]] && break
  echo "The instance in state $state. Waiting."
  sleep 5
done

exec <%= @runner_package_directory %>/bin/runsvc.sh
```

The `exec` replaces the bash PID with runsvc.sh, so systemd's SIGTERM
goes directly to runsvc.sh (which traps TERM→INT and forwards to
Runner.Listener). Bash's own signal handling during the pre-InService
wait loop is fine: SIGTERM during `sleep` kills the script, and there's
no runner to stop yet at that point.

## 3. New script — `gha-on-runner-exit.sh`

File: `environments/development/modules/profile/files/github_runner/gha-on-runner-exit.sh`
(managed by `service.pp`).

```bash
#!/usr/bin/env bash
# Called by systemd's ExecStopPost when actions-runner.service stops.
# If the ASG wants this instance terminated, complete the deregistration
# lifecycle hook now so the instance can go away cleanly.
set -eu

hook_name="${DEREGISTRATION_HOOK_NAME:-}"
[[ -z "$hook_name" ]] && exit 0  # old-Terraform ASG — old Lambda handles it

instance_id=$(ec2metadata --instance-id)
state=$(aws autoscaling describe-auto-scaling-instances \
        --instance-ids "$instance_id" \
        --query 'AutoScalingInstances[0].LifecycleState' --output text 2>/dev/null || echo "")

case "$state" in
  Terminating:Wait|Terminating:Proceed)
    ih-aws autoscaling complete --hook "$hook_name" --result CONTINUE
    ;;
esac
```

Uses the existing `ih-aws autoscaling complete` subcommand
(cmd_autoscaling/cmd_complete/__init__.py in infrahouse-toolkit), which
auto-resolves instance_id / asg_name from IMDS.

## 4. New systemd heartbeater

Two new files under `environments/development/modules/profile/files/github_runner/`
+ manifest wiring.

**`gha-lifecycle-heartbeater.sh`:**
```bash
#!/usr/bin/env bash
# No-op unless the instance is in Terminating:Wait. Fire-and-forget.
set -eu

hook_name="${DEREGISTRATION_HOOK_NAME:-}"
[[ -z "$hook_name" ]] && exit 0

instance_id=$(ec2metadata --instance-id)
state=$(aws autoscaling describe-auto-scaling-instances \
        --instance-ids "$instance_id" \
        --query 'AutoScalingInstances[0].LifecycleState' --output text 2>/dev/null || echo "")

if [[ "$state" == "Terminating:Wait" ]]; then
  asg=$(ih-ec2 tags | jq -r '."aws:autoscaling:groupName"')
  aws autoscaling record-lifecycle-action-heartbeat \
    --auto-scaling-group-name "$asg" \
    --lifecycle-hook-name "$hook_name" \
    --instance-id "$instance_id"
fi
```

**`gha-lifecycle-heartbeater.service`:**
```
[Unit]
Description=Extend deregistration lifecycle hook while this instance is terminating

[Service]
Type=oneshot
ExecStart=/usr/local/bin/gha-lifecycle-heartbeater.sh
Environment=DEREGISTRATION_HOOK_NAME=<%= @deregistration_hookname %>
Restart=on-failure
```

**`gha-lifecycle-heartbeater.timer`:**
```
[Unit]
Description=Every 10 minutes, heartbeat the deregistration lifecycle hook if needed

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Unit=gha-lifecycle-heartbeater.service

[Install]
WantedBy=timers.target
```

Timer fires every 10min. Heartbeat with `heartbeat_timeout=30min` gives
3 attempts before expiry — enough slack for a transient API error. No
metric, no alarm.

## 5. Update `gha_prerun.sh`

`environments/development/modules/profile/files/github_runner/gha_prerun.sh`:

```bash
#!/usr/bin/env bash
set -eu

sudo chown -R "$USER" "$GITHUB_WORKSPACE"

# Try to protect this instance from scale-in. If the ASG has already
# decided to terminate us, protection is meaningless; let the job run
# and let the deprovisioning path finish us off cleanly.
if ! /usr/local/bin/ih-aws autoscaling scale-in enable-protection 2>/tmp/prerun_err; then
  instance_id=$(ec2metadata --instance-id)
  state=$(aws autoscaling describe-auto-scaling-instances \
          --instance-ids "$instance_id" \
          --query 'AutoScalingInstances[0].LifecycleState' --output text 2>/dev/null || echo "")
  case "$state" in
    Terminating:Wait|Terminating:Proceed)
      echo "prerun: instance is in $state — skipping protect, job will proceed" >&2
      ;;
    *)
      cat /tmp/prerun_err >&2
      exit 1
      ;;
  esac
fi
```

Keeps existing behavior for real errors; only the specific
"we're already terminating" path gets tolerated.

## 6. `gha_postrun.sh` — unchanged

Keep the existing `disable-protection || true` behavior. The new
`ExecStopPost` hook and the heartbeater handle the new responsibilities.

## 7. Delete the registration token after register

In `environments/development/modules/profile/manifests/github_runner/register.pp`,
add a separate `delete_registration_token` exec that fires via
`notify`/`refreshonly`. No error swallowing — if the delete genuinely
fails, Puppet reports it and the operator investigates.

```puppet
exec { 'register_runner':
  user    => $user,
  path    => "/usr/bin:/usr/local/bin:${runner_package_directory}",
  cwd     => $runner_package_directory,
  command => "ih-github runner --registration-token-secret ${token_secret} --org ${org} register \
--actions-runner-code-path ${runner_package_directory} ${url} ${labels_arg}",
  creates => "${runner_package_directory}/.credentials",
  require => [ Exec[extract_runner_package] ],
  notify  => Exec['delete_registration_token'],
}

exec { 'delete_registration_token':
  user        => $user,
  path        => "/usr/bin:/usr/local/bin",
  command     => "aws secretsmanager delete-secret --secret-id ${token_secret} --force-delete-without-recovery",
  refreshonly => true,
}
```

Flow:
- First Puppet run on a fresh instance: `register_runner` runs → notify
  fires → `delete_registration_token` runs → secret deleted.
- Subsequent Puppet runs: `register_runner` skipped (`.credentials`
  exists) → nothing to notify → `delete_registration_token` skipped.
- If `register_runner` fails: notify does not fire (Puppet only
  refreshes subscribers when the resource completes successfully).
  Token lingers, but the instance is unhealthy, `check-health` cron
  marks it so, ASG replaces it, and the deregistration Lambda cleans up
  the secret as part of termination.
- If `delete_registration_token` itself fails (e.g. `AccessDenied` on
  old-Terraform ASGs lacking the IAM): Puppet reports the failure.
  Intentional — we'd rather see the IAM gap than paper over it.

## 8. Puppet manifest wiring

Update `environments/development/modules/profile/manifests/github_runner/service.pp`
to manage:
- `/usr/local/bin/gha-on-runner-exit.sh`
- `/usr/local/bin/gha-lifecycle-heartbeater.sh`
- `/etc/systemd/system/gha-lifecycle-heartbeater.service` (ERB template
  — needs `@deregistration_hookname`)
- `/etc/systemd/system/gha-lifecycle-heartbeater.timer`
- enable + start the `.timer` unit.
- Pass `@deregistration_hookname` from `$facts['deregistration_hookname']`
  (with empty-string fallback) to the `actions-runner.service.erb` and
  `gha-lifecycle-heartbeater.service` templates.

## 9. Promotion sequence (later, not part of initial PR)

After Part 2 changes are working end-to-end in
`environments/development/` (verified by at least one successful
scale-in with a job in-flight):

1. Copy all files to `environments/sandbox/modules/profile/github_runner/`.
2. Bump `terraform-aws-actions-runner` module version in the sandbox
   AWS account (Part 1 release).
3. **Observe for a week** — watch for `ValidationError` on
   `SetInstanceProtection` in CloudTrail, stuck `Terminating:Wait`
   instances, and prerun failures.
4. Copy to top-level `modules/profile/github_runner/` (global) and bump
   `terraform-aws-actions-runner` version in all remaining environments.

Each promotion is a separate PR.

---

# Backwards compatibility

The only realistic mixed state is **new-Puppet + old-Terraform** — a
runner that already has this Puppet profile but whose ASG still uses
the pre-change Terraform module. That instance:

- Has no `deregistration_hookname` fact → systemd `Environment=` is
  empty → `ExecStopPost` and heartbeater scripts both exit 0 as
  no-ops.
- Has the old deregistration Lambda still wired up — it handles
  lifecycle completion via the existing path, so instances still
  terminate cleanly.
- Lacks `secretsmanager:DeleteSecret` on its instance profile → the
  new `delete_registration_token` exec will fail with
  `AccessDeniedException`. Puppet reports the failure. One failed
  agent run per instance until Terraform is bumped. Token cleanup
  falls back to the old Lambda on termination (same as today). We
  intentionally do not swallow this error — we want the IAM gap
  visible.
- Benefits *already* from §1 and §2 regardless of Terraform: short
  jobs hitting the scale-in race survive via prerun tolerance, and
  the systemd `KillMode=process` + `TimeoutStopSec` fix stops the
  cgroup-wide SIGKILL that currently kills in-flight jobs at 90s.

Net: strictly an improvement over today. No regression risk.

---

# What we rely on (no new toolkit work)

- **Existing `ih-aws autoscaling complete --hook <name> [--result ...]`**
  in infrahouse-toolkit (cmd_autoscaling/cmd_complete/__init__.py:20).
  Auto-resolves instance_id/asg_name from IMDS via `ASGInstance`.
- **Existing `ih-aws autoscaling scale-in
  enable-protection|disable-protection`** (used today by
  gha_prerun.sh / gha_postrun.sh).
- **Existing `ih-ec2 tags`** for ASG-name lookup from EC2 tags.
- **Raw AWS CLI** for
  `aws autoscaling describe-auto-scaling-instances`,
  `aws autoscaling record-lifecycle-action-heartbeat`, and
  `aws secretsmanager delete-secret`.

No new `ih-aws` subcommands, no infrahouse-core changes.

---

# Risks to watch for during implementation

1. **Heartbeater robustness.** Three missed fires in a row → hook times
   out → instance dies mid-job. Consider a simple retry loop inside the
   script for transient `aws` CLI failures.
2. **`TimeoutStopSec=21600`** means `systemctl stop actions-runner` can
   block for 6h on a debugging instance. AWS force-terminates before
   that, so production impact is nil, but document for operators.
3. **Empty-`Environment=` behavior.** If the ERB renders
   `Environment=DEREGISTRATION_HOOK_NAME=` (literal empty value),
   systemd accepts it and the script sees `$DEREGISTRATION_HOOK_NAME=""`.
   Verify during dev.
4. **Warm-pool trim path.** The deregistration Lambda still short-circuits
   on `Warmed:Terminating:Wait`. Confirm heartbeater no-ops correctly
   on warm-pool instances (they're hibernated so timer shouldn't fire
   anyway, but worth verifying on a test ASG with a shrinking warm
   pool).

---

# Success criteria

- A test job that lands in the scale-in race window runs to completion
  (no exit 1 from prerun), postrun runs, runner exits via SIGTERM,
  `ExecStopPost` completes the lifecycle action, instance terminates.
- No `ValidationError` on `SetInstanceProtection` in CloudTrail during
  scale-in events.
- Heartbeater successfully extends the lifecycle hook during long
  (`>30min`) `Terminating:Wait` windows.
- `gha_postrun.sh` and `gha_prerun.sh` still work for the common case
  (InService runner, short jobs).
