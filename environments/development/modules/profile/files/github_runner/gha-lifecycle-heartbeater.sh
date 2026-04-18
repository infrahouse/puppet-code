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
