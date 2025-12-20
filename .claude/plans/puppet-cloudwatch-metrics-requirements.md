# Technical Requirements: CloudWatch Metrics for Jumphost Audit and Security Monitoring

## Document Information
- **Created**: 2025-12-19
- **Target Audience**: Puppet Module Maintainers
- **Related Terraform Module**: terraform-aws-jumphost
- **Status**: Draft for Implementation

## Executive Summary

This document outlines the requirements for implementing CloudWatch custom metrics in the Puppet configuration that manages AWS jumphost instances. These metrics are essential for security monitoring, compliance, and operational alerting.

The Terraform module already provisions:
- CloudWatch log groups for audit trails
- IAM permissions for metric publishing
- CloudWatch alarms that will consume these metrics

**Puppet's responsibility**: Configure the CloudWatch agent to publish the required custom metrics.

---

## Background and Context

### What is the Jumphost Module?

The `terraform-aws-jumphost` Terraform module creates AWS bastion hosts (jumphosts) that provide SSH access to private network resources. Key characteristics:

- **Security-Critical Infrastructure**: These hosts are the entry point to private networks
- **Compliance Requirements**: Must maintain detailed audit logs and monitoring
- **Always-On CloudWatch Logging**: Log group created at `/aws/ec2/jumphost/{environment}/{hostname}`
- **Puppet-Managed Configuration**: Instances are configured via Puppet after launch
- **Multi-Instance Support**: Multiple jumphosts can run in same environment with unique hostnames

### Why These Metrics Are Needed

Jumphosts are high-value security targets. We need real-time monitoring to detect:

1. **Security Incidents**: Failed SSH login attempts, unauthorized access patterns
2. **Audit System Failures**: Lost audit events indicate potential security blind spots
3. **Service Availability**: Audit daemon downtime creates compliance gaps
4. **Operational Issues**: Disk space exhaustion can cause service disruption

These metrics enable CloudWatch alarms that alert security and operations teams to take immediate action.

### Current Infrastructure State

**Already Implemented in Terraform** (`cloudwatch-logs.tf`):

```hcl
# IAM permissions for CloudWatch agent (lines 32-46)
statement {
  sid    = "CloudWatchMetrics"
  effect = "Allow"
  actions = [
    "cloudwatch:PutMetricData"
  ]
  resources = ["*"]

  condition {
    test     = "StringEquals"
    variable = "cloudwatch:namespace"
    values   = ["Jumphost/System"]  # ← Metrics MUST use this namespace
  }
}
```

**CloudWatch Log Group** (created per instance):
- Name pattern: `/aws/ec2/jumphost/{environment}/{hostname}`
- Retention: 365 days (default, configurable)
- Optional KMS encryption support
- IAM permissions for log publishing already granted

**Puppet Facts Available**:
The Terraform module passes these facts to Puppet via cloud-init:
- `jumphost.cloudwatch_log_group`: Full log group name (e.g., `/aws/ec2/jumphost/production/jumphost`)
- `environment`: Environment name (e.g., `production`, `staging`)
- `hostname`: The Route53 hostname assigned to this jumphost

---

## Technical Requirements

### Metric Namespace and Dimensions

All metrics MUST use these exact specifications to match IAM permissions and CloudWatch alarms:

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Namespace** | `Jumphost/System` | Hardcoded in IAM policy, cannot be changed |
| **Dimension: Hostname** | `{ec2_instance_hostname}` | EC2 instance's actual hostname (e.g., `ip-10-0-1-5`), NOT the Route53/NLB name |
| **Dimension: Environment** | `{environment}` | From Puppet fact |

**Why EC2 Instance Hostname?**

The jumphost service uses an NLB that forwards to multiple EC2 instances in an Auto Scaling Group. Each instance has its own hostname like `ip-10-0-1-5`. These metrics are **instance-level** (auditd status, disk space, login attempts on a specific instance), not service-level. Using the EC2 instance hostname allows you to identify exactly which instance is having issues when an alarm triggers.

**Example Dimensions**:
```json
{
  "Hostname": "ip-10-0-1-5",
  "Environment": "production"
}
```

### Required Metrics

#### 1. ServiceStatus - Audit Daemon Health Check

**Purpose**: Monitors if the audit daemon (`auditd`) is running. Critical for compliance.

| Property | Value |
|----------|-------|
| Metric Name | `ServiceStatus` |
| Unit | `None` |
| Value | `1` if auditd is running, `0` if not |
| Collection Frequency | Every 60 seconds |
| Method | Process monitoring (check if `auditd` process exists) |

**Implementation Notes**:
- ✅ Implemented as custom metric via `/usr/local/bin/publish-jumphost-metrics` script
- Uses `pidof auditd` to check actual process state (not systemd status)
- Published every 60 seconds via cron

**✅ FINAL IMPLEMENTATION NOTE FOR TERRAFORM TEAM**:
All metrics are published using custom script with `aws cloudwatch put-metric-data`. Metric names match requirements exactly:
- **Metric Name**: `ServiceStatus` (as originally specified)
- **Behavior**: Value of 1 if auditd running, 0 if not
- **Dimensions**: `Hostname` (EC2 instance hostname), `Environment`
- **Collection**: Every 60 seconds

**Alarm Configuration** (for context):
- Alert if `ServiceStatus < 1` for 5 minutes
- Severity: Critical (page on-call)

---

#### 2. AuditEventsLost - Audit Event Loss Detection

**Purpose**: Detects when audit events are being dropped due to buffer overflow or system load.

| Property | Value |
|----------|-------|
| Metric Name | `AuditEventsLost` |
| Unit | `Count` |
| Value | Number of audit events lost since last collection |
| Collection Frequency | Every 60 seconds |
| Method | Parse `auditctl -s` or `/proc/self/audit/lost` |

**Implementation Notes**:
- Parse output of `auditctl -s` and extract the `lost` counter
- Report the **delta** (increase since last check), not cumulative total
- If `auditctl` command unavailable, check `/var/log/audit/audit.log` for lost event messages

**Example `auditctl -s` Output**:
```
enabled 1
failure 1
pid 1234
rate_limit 0
backlog_limit 8192
lost 0          ← This value
backlog 0
```

**Alarm Configuration** (for context):
- Alert if `AuditEventsLost > 0` (any lost events)
- Severity: Critical (alert security team)

---

#### 3. DiskSpaceUsed - Root Filesystem Usage

**Purpose**: Monitors disk space to prevent service disruption from full filesystems.

| Property | Value |
|----------|-------|
| Metric Name | `DiskSpaceUsed` |
| Unit | `Percent` |
| Value | Percentage of root filesystem used (0-100) |
| Collection Frequency | Every 300 seconds (5 minutes) |
| Method | CloudWatch agent `disk` plugin |

**Implementation Notes**:
- Monitor the root filesystem (`/`)
- Report as percentage (e.g., `85.5` for 85.5% used)
- Should reflect actual disk usage (`df -h /` equivalent)

**Alarm Configuration** (for context):
- Alert if `DiskSpaceUsed > 90%`
- Severity: Medium (alert ops team)

---

#### 4. FailedLogins - SSH Authentication Failures

**Purpose**: Detects brute-force attacks or unauthorized access attempts.

| Property | Value |
|----------|-------|
| Metric Name | `FailedLogins` |
| Unit | `Count` |
| Value | Number of failed SSH login attempts since last collection |
| Collection Frequency | Every 60 seconds |
| Method | Parse auth logs or audit logs for failed SSH authentications |

**Implementation Notes**:
- Parse `/var/log/auth.log` (Ubuntu) for failed SSH authentications
- Look for patterns:
    - `Failed password for`
    - `authentication failure`
    - `Connection closed by authenticating user`
- Report **delta** (new failures since last check), not cumulative
- Consider using `audit` rules for SSH events (more reliable than log parsing)

**Example Log Entries to Match**:
```
Dec 19 10:15:23 jumphost sshd[12345]: Failed password for invalid user admin from 192.0.2.1 port 54321 ssh2
Dec 19 10:15:25 jumphost sshd[12346]: Failed password for ubuntu from 192.0.2.1 port 54322 ssh2
```

**Alarm Configuration** (for context):
- Alert if `FailedLogins > 10` in 5 minutes
- Severity: High (alert security team)

---

## Implementation Guidance

### CloudWatch Agent Configuration

The CloudWatch agent should be installed and configured via Puppet. Below is a reference configuration structure:

#### Recommended Approach: CloudWatch Agent JSON Config

**File Location**: `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`

**Configuration Template**:
```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "region": "us-west-1",
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "Jumphost/System",
    "metrics_collected": {
      "procstat": [
        {
          "pattern": "auditd",
          "measurement": [
            {
              "name": "pid_count",
              "rename": "ServiceStatus"
            }
          ],
          "metrics_collection_interval": 60
        }
      ],
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DiskSpaceUsed"
          }
        ],
        "metrics_collection_interval": 300,
        "resources": [
          "/"
        ]
      }
    },
    "append_dimensions": {
      "Hostname": "${hostname_from_puppet_fact}",
      "Environment": "${environment_from_puppet_fact}"
    }
  }
}
```

**Notes**:
- Replace `${hostname_from_puppet_fact}` with EC2 instance hostname (e.g., `ip-10-0-1-5`) from Puppet
- Replace `${environment_from_puppet_fact}` with environment value from Puppet
- **CRITICAL**: Use EC2 instance hostname, NOT Route53 hostname
- CloudWatch agent package: `amazon-cloudwatch-agent` (available in Ubuntu repos)

#### Custom Metrics: AuditEventsLost and FailedLogins

These metrics require custom scripts since they're not natively supported by the CloudWatch agent.

**Option A: Custom Script with CloudWatch Agent StatsD**

Configure CloudWatch agent to accept StatsD metrics:
```json
{
  "metrics": {
    "namespace": "Jumphost/System",
    "metrics_collected": {
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 60,
        "metrics_aggregation_interval": 60
      }
    }
  }
}
```

Then create a cron job that runs a script every minute:

**Script: `/usr/local/bin/publish-audit-metrics.sh`**
```bash
#!/bin/bash
set -euo pipefail

# Get values from Puppet facts
# CRITICAL: Use EC2 instance hostname (e.g., ip-10-0-1-5), NOT Route53 hostname
HOSTNAME="<%= @ec2_hostname %>"  # From $facts['networking']['hostname']
ENVIRONMENT="<%= @environment %>"
STATSD_HOST="localhost:8125"

# 1. Check AuditEventsLost
LOST_EVENTS=$(auditctl -s 2>/dev/null | grep '^lost' | awk '{print $2}' || echo "0")
LAST_LOST=$(cat /var/run/audit-lost-count.txt 2>/dev/null || echo "0")
DELTA_LOST=$((LOST_EVENTS - LAST_LOST))
echo "$LOST_EVENTS" > /var/run/audit-lost-count.txt

if [ "$DELTA_LOST" -gt 0 ]; then
  echo "AuditEventsLost:${DELTA_LOST}|c|#Hostname:${HOSTNAME},Environment:${ENVIRONMENT}" | nc -u -w1 $STATSD_HOST
fi

# 2. Check FailedLogins
CURRENT_TIMESTAMP=$(date +%s)
LAST_TIMESTAMP=$(cat /var/run/failed-login-timestamp.txt 2>/dev/null || echo "0")
FAILED_COUNT=$(journalctl -u ssh.service --since="@${LAST_TIMESTAMP}" 2>/dev/null | \
  grep -c "Failed password" || echo "0")
echo "$CURRENT_TIMESTAMP" > /var/run/failed-login-timestamp.txt

if [ "$FAILED_COUNT" -gt 0 ]; then
  echo "FailedLogins:${FAILED_COUNT}|c|#Hostname:${HOSTNAME},Environment:${ENVIRONMENT}" | nc -u -w1 $STATSD_HOST
fi
```

**Cron Entry**:
```
* * * * * /usr/local/bin/publish-audit-metrics.sh
```

**Option B: AWS CLI PutMetricData**

Alternative approach using `aws cloudwatch put-metric-data`:

```bash
#!/bin/bash
aws cloudwatch put-metric-data \
  --namespace Jumphost/System \
  --metric-name AuditEventsLost \
  --value "$DELTA_LOST" \
  --dimensions Hostname="$HOSTNAME",Environment="$ENVIRONMENT" \
  --region us-west-1
```

**Pros/Cons**:
- **StatsD (Option A)**: Better performance, single agent, more complex setup
- **AWS CLI (Option B)**: Simpler, more direct, requires AWS CLI installed

---

## Puppet Fact Integration

The Terraform module passes configuration via Puppet facts. Access them in Puppet manifests:

**Available Facts**:
```puppet
$log_group_name = $facts['jumphost']['cloudwatch_log_group']
$environment    = $facts['environment']
$route53_name   = $facts['hostname']  # Route53 hostname (e.g., "jumphost") - used for log group naming
```

**Getting the EC2 Instance Hostname**:

For CloudWatch metrics, you MUST use the EC2 instance's actual hostname (e.g., `ip-10-0-1-5`), not the Route53 name. Use one of these approaches:

**Option 1: Puppet networking fact (recommended)**:
```puppet
$ec2_hostname = $facts['networking']['hostname']  # Returns "ip-10-0-1-5"
```

**Option 2: System hostname**:
```puppet
$ec2_hostname = $facts['fqdn'].split('.')[0]  # Extract hostname from FQDN
```

**Option 3: EC2 metadata service**:
```bash
# In a template or exec resource
HOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname | cut -d'.' -f1)
```

**Example Puppet Usage**:
```puppet
# Configure CloudWatch agent with proper dimensions
$ec2_hostname = $facts['networking']['hostname']  # e.g., "ip-10-0-1-5"
$environment  = $facts['environment']              # e.g., "production"

file { '/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json':
  content => template('jumphost/cloudwatch-agent-config.json.erb'),
  notify  => Service['amazon-cloudwatch-agent'],
}

# Template uses:
# - <%= @ec2_hostname %>     # For metric Hostname dimension
# - <%= @environment %>       # For metric Environment dimension
```

**CRITICAL**:
- **DO use**: EC2 instance hostname (e.g., `ip-10-0-1-5`) for CloudWatch metric dimensions
- **DO NOT use**: Route53 hostname (e.g., `jumphost`) for metric dimensions
- **DO NOT use**: EC2 instance ID (e.g., `i-1234567890abcdef0`)

The EC2 instance hostname allows ops teams to identify which specific instance triggered an alarm in a multi-instance Auto Scaling Group.

---

## Testing and Validation

### Metric Publication Test

After implementing, verify metrics are being published:

```bash
# On the jumphost instance
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
```

**Expected Output**: Agent should show status "running"

### AWS Console Verification

Check metrics in AWS CloudWatch console:

1. Navigate to CloudWatch → Metrics
2. Select namespace: `Jumphost/System`
3. Verify dimensions: `Hostname`, `Environment`
4. Confirm metrics appearing:
    - `ServiceStatus`
    - `AuditEventsLost`
    - `DiskSpaceUsed`
    - `FailedLogins`

### AWS CLI Verification

```bash
# Replace ip-10-0-1-5 with your actual EC2 instance hostname
aws cloudwatch get-metric-statistics \
  --namespace Jumphost/System \
  --metric-name ServiceStatus \
  --dimensions Name=Hostname,Value=ip-10-0-1-5 Name=Environment,Value=production \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average
```

**Expected Output**: Should return datapoints with values

**Note**: Use the EC2 instance hostname (e.g., `ip-10-0-1-5`), not the Route53 hostname

---

## Security Considerations

### Principle of Least Privilege

IAM permissions are already restricted to:
- **Action**: `cloudwatch:PutMetricData` only
- **Condition**: Namespace MUST be `Jumphost/System`

The instance profile cannot publish metrics to other namespaces or modify CloudWatch configuration.

### Sensitive Data in Metrics

**DO NOT include**:
- Usernames in metric dimensions
- IP addresses in metric dimensions
- Any PII (Personally Identifiable Information)

Metric values should be **aggregated counts only**. Detailed audit trails belong in CloudWatch Logs (already configured), not metrics.

### Audit Log Parsing Security

If parsing `/var/log/auth.log`:
- Ensure script has minimal privileges
- Use read-only access
- Do not modify audit logs
- Handle log rotation properly (use `journalctl` when possible)

---

## Dependencies and Prerequisites

### Required Packages

Install these packages via Puppet:
- `amazon-cloudwatch-agent` - CloudWatch agent for metric publishing
- `auditd` - Audit daemon (should already be installed)
- `netcat-openbsd` - If using StatsD approach (for `nc` command)

### Required Services

Ensure these services are enabled and running:
- `auditd.service` - Audit daemon
- `amazon-cloudwatch-agent.service` - CloudWatch agent

### IAM Permissions

**Already granted by Terraform module** - no action needed:
- `cloudwatch:PutMetricData` (with namespace restriction)
- `logs:CreateLogStream`, `logs:PutLogEvents` - for CloudWatch Logs

---

## Rollout Strategy

### Phase 1: Development Environment
1. Implement CloudWatch agent configuration in Puppet
2. Deploy to dev/staging jumphost
3. Validate metrics appear in CloudWatch console
4. Verify metric dimensions are correct

### Phase 2: Terraform Integration
1. Enable audit alarms in Terraform module: `enable_audit_alarms = true`
2. Verify alarms are created and linked to metrics
3. Test alarm triggering (simulate failures)

### Phase 3: Production Rollout
1. Deploy Puppet changes to production jumphosts
2. Monitor for 24-48 hours
3. Verify no false positives from alarms
4. Document runbook for alarm responses

---

## Support and Troubleshooting

### CloudWatch Agent Logs

Check agent logs if metrics aren't appearing:
```bash
tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

**Common Issues**:
- **"No credentials found"**: Check IAM instance profile is attached
- **"AccessDenied"**: Verify namespace is exactly `Jumphost/System`
- **"Invalid dimensions"**: Check dimension names match: `Hostname`, `Environment`

### Metric Not Appearing

1. **Check agent status**:
   ```bash
   systemctl status amazon-cloudwatch-agent
   ```

2. **Verify IAM permissions**:
   ```bash
   aws sts get-caller-identity  # Should return instance role
   ```

3. **Test metric publication manually**:
   ```bash
   aws cloudwatch put-metric-data \
     --namespace Jumphost/System \
     --metric-name TestMetric \
     --value 1 \
     --dimensions Hostname=test,Environment=test
   ```

4. **Check CloudWatch agent config**:
   ```bash
   /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
     -a fetch-config \
     -m ec2 \
     -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
     -s
   ```

### Getting Help

- **Terraform Module Issues**: https://github.com/infrahouse/terraform-aws-jumphost/issues
- **CloudWatch Agent Docs**: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html
- **Puppet Module Maintainers**: [Contact info here]

---

## Appendix A: Complete Example Configuration

### Puppet Manifest Example

```puppet
class jumphost::monitoring {
  # Install CloudWatch agent
  package { 'amazon-cloudwatch-agent':
    ensure => installed,
  }

  # Get facts from Terraform and system
  $route53_name = $facts['hostname']                     # Route53 hostname (e.g., "jumphost")
  $ec2_hostname = $facts['networking']['hostname']       # EC2 instance hostname (e.g., "ip-10-0-1-5")
  $environment  = $facts['environment']                  # Environment (e.g., "production")
  $log_group    = $facts['jumphost']['cloudwatch_log_group']

  # Deploy CloudWatch agent configuration
  file { '/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json':
    ensure  => file,
    content => template('jumphost/cloudwatch-agent.json.erb'),
    require => Package['amazon-cloudwatch-agent'],
    notify  => Service['amazon-cloudwatch-agent'],
  }

  # Deploy custom metrics script
  file { '/usr/local/bin/publish-audit-metrics.sh':
    ensure  => file,
    mode    => '0755',
    content => template('jumphost/publish-audit-metrics.sh.erb'),
  }

  # Cron job for custom metrics
  cron { 'publish-audit-metrics':
    command => '/usr/local/bin/publish-audit-metrics.sh',
    user    => 'root',
    minute  => '*',
    require => File['/usr/local/bin/publish-audit-metrics.sh'],
  }

  # Ensure CloudWatch agent is running
  service { 'amazon-cloudwatch-agent':
    ensure  => running,
    enable  => true,
    require => [
      Package['amazon-cloudwatch-agent'],
      File['/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json'],
    ],
  }

  # Ensure auditd is running
  service { 'auditd':
    ensure => running,
    enable => true,
  }
}
```

---

## Appendix B: Metric Schema Reference

Quick reference table for implementation:

| Metric Name | Namespace | Dimensions | Unit | Collection Interval | Source |
|-------------|-----------|------------|------|---------------------|--------|
| ServiceStatus | Jumphost/System | Hostname, Environment | None | 60s | Custom script (pidof auditd) |
| AuditEventsLost | Jumphost/System | Hostname, Environment | Count | 60s | Custom script (auditctl -s) |
| DiskSpaceUsed | Jumphost/System | Hostname, Environment | Percent | 60s | Custom script (df -h /) |
| FailedLogins | Jumphost/System | Hostname, Environment | Count | 60s | Custom script (journalctl) |

**✅ All metrics implemented via custom script** (`/usr/local/bin/publish-jumphost-metrics`) using `aws cloudwatch put-metric-data` for full control over metric names and dimensions.

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2025-12-19 | 1.3 | Claude Code | **FINAL**: All metrics implemented via custom script (`/usr/local/bin/publish-jumphost-metrics`). CloudWatch agent `append_dimensions` feature doesn't work reliably, so custom approach used for full control. All metric names match requirements exactly. |
| 2025-12-19 | 1.2 | Claude Code | Added note for Terraform team: procstat plugin cannot rename metrics, actual metric name is `procstat_lookup_pid_count` not `ServiceStatus` |
| 2025-12-19 | 1.1 | Claude Code | Critical fix: Changed Hostname dimension to use EC2 instance hostname instead of Route53 hostname for proper instance identification in ASG |
| 2025-12-19 | 1.0 | Claude Code | Initial draft |
