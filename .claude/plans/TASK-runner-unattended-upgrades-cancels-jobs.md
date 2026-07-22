# Task: unattended-upgrades restarts actions-runner mid-job, cancelling CI jobs

## Symptom

GitHub Actions jobs on the self-hosted runner fleet (`actions-runner-…` ASG,
us-west-1) get cancelled mid-run with `##[error] The operation was canceled`,
followed by "Terminate orphan process" cleanup of `make`/`pytest`/`terraform`.
The **runner instance stays alive and healthy** — it is the *job* that dies, not
the box. Because the job dies mid-`terraform apply`, pytest never runs its
teardown, so **AWS test resources leak** and have to be cleaned up by hand.

It happens at **random points** in a run (seen ~20 min in during a Puppet wait,
and ~90 s in during `terraform apply`), which made it look like flaky infra.

Concrete case: run `terraform-aws-openvpn` PR #81, job on runner `ip-10-0-1-59`
(`i-0ee5dd25d62d63956`) — instance was `InService` + `ProtectedFromScaleIn: true`
the whole time, yet the job was cancelled at 18:32:24Z.

## Root cause (confirmed from the runner's own logs)

Ubuntu's **`apt-daily-upgrade.service` (unattended-upgrades)** fires on a
randomized daily timer, and the post-upgrade **`needrestart`** pass restarts every
service linked against an updated shared library — **including
`actions-runner.service`**. Restarting the runner agent mid-job cancels the job.

systemd journal on the runner (`i-0ee5dd25d62d63956`, all UTC):

```
18:31:48  systemd[1]: Starting apt-daily-upgrade.service - Daily apt upgrade and clean activities...
18:32:10  systemd[1]: Stopping actions-runner.service - GitHub self-hosted runner...   <-- killed here
18:32:33  systemd[1]: actions-runner.service: Deactivated / Stopped / Started
```
(Same pass also bounced fwupd, packagekit, snapd, postfix, rpcbind — the usual
needrestart list after a libssl/glibc-class update.)

Runner listener log at the same moment:
```
18:32:11Z ERR  BrokerServer  System.ObjectDisposedException: ... 'System.Net.Sockets.NetworkStream'
18:32:11Z INFO JobDispatcher  Shutting down JobDispatcher... cancel any running job.
18:32:29Z INFO JobDispatcher  finish job request ... with result: Canceled
18:32:30Z INFO Listener       Runner execution been cancelled.
```

The randomized timer (`apt-daily-upgrade.timer` has a large `RandomizedDelaySec`)
explains the random kill-point across runs. This is **not** scale-in / instance
termination — an earlier idle instance (`i-0e300d…`) was scaled in separately and
was a red herring; the job ran on a healthy protected runner.

## Fix (goal: keep patching, never restart the runner mid-job)

We WANT unattended-upgrades to keep applying security patches. We do NOT want it
to restart `actions-runner.service`. Two parts:

### 1. Exclude actions-runner from needrestart auto-restart
Drop a needrestart override (Puppet-managed file on the runner):

```perl
# /etc/needrestart/conf.d/actions-runner.conf
# Keep unattended-upgrades patching the box, but never restart the CI runner
# mid-job — restarting actions-runner.service cancels the running GitHub job.
$nrconf{override_rc} = {
    qr(^actions-runner\.service$) => 0,   # 0 = skip restart, 1 = force
};
```
(Confirm `override_rc` semantics on the installed needrestart version — noble ships
a recent one; `=> 0` = do-not-restart is the documented knob.)

### 2. Restart the runner only when idle (so patches still land)
Excluding it means the runner keeps running the pre-upgrade libraries until it is
restarted some other way. Restart `actions-runner.service` **only when no job is
running**, e.g.:
- from the job-completed hook (`gha_postrun.sh` / `ACTIONS_RUNNER_HOOK_JOB_COMPLETED`), or
- a small systemd timer / cron that restarts the service only if the runner is idle
  (no active Worker / job).

Leave `Unattended-Upgrade::Automatic-Reboot` as-is unless kernel-update reboots are
also cancelling jobs — same idea applies (reboot only when idle).

## Acceptance

- unattended-upgrades still runs and applies package updates on the runner.
- A `needrestart` pass triggered by an upgrade does **not** stop/restart
  `actions-runner.service` while a job is running (verify: run an upgrade during a
  job; job survives; journal shows no `Stopping actions-runner.service`).
- The runner still gets restarted (to pick up patched libs) when idle.
- No more mid-run `The operation was canceled` from this cause; no leaked test infra.

## Scope / notes

- Where this lives: the Puppet profile/module that builds the `actions-runner`
  AMI / configures the runner instances (this repo, or the runner module referenced
  from `aws-control`). Find the class managing `actions-runner.service` and add the
  needrestart drop-in + idle-restart there.
- Unrelated to terraform-aws-openvpn PR #81 — that change is correct; it was just
  the victim that surfaced this. Validate #81 locally with `make test-clean` (self-
  destroys its stack) rather than waiting on the fleet.
- Separately worth a look (lower priority, not the cause here): the fleet flaps
  (`IdleRunnersTooHigh`/`Low` oscillating desired 1↔2 every ~15 min), and the
  scale-in protection model is job-start-triggered (`gha_prerun.sh` calls
  `ih-aws autoscaling scale-in enable-protection`, giving up if already
  `Terminating:Wait`). Not what cancelled these jobs, but a source of churn.