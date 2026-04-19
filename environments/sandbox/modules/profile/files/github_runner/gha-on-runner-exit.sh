#!/usr/bin/env bash
# Called by systemd's ExecStopPost when actions-runner.service stops.
# If the ASG wants this instance terminated, complete the deregistration
# lifecycle hook now so the instance can go away cleanly.
set -eu

hook_name="${DEREGISTRATION_HOOK_NAME:-}"
[[ -z "$hook_name" ]] && exit 0

instance_id=$(ec2metadata --instance-id)
state=$(aws autoscaling describe-auto-scaling-instances \
        --instance-ids "$instance_id" \
        --query 'AutoScalingInstances[0].LifecycleState' --output text 2>/dev/null || echo "")

case "$state" in
  Terminating:Wait|Terminating:Proceed)
    /usr/local/bin/ih-aws autoscaling complete --result CONTINUE "$hook_name"
    ;;
esac
