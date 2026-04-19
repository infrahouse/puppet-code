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
