# Implementation Plan: CloudWatch Metrics for Jumphost

## Document Information
- **Created**: 2025-12-19
- **Status**: Ready for Implementation
- **Related Requirements**: [puppet-cloudwatch-metrics-requirements.md](./puppet-cloudwatch-metrics-requirements.md)
- **Scope**: Extend Puppet jumphost profile to publish CloudWatch custom metrics
- **Target Environments**: Development → Sandbox → Production
- **Estimated Effort**: 3-5 days

---

## Executive Summary

This implementation plan outlines the tasks required to extend the Puppet `profile::jumphost` module 
to publish CloudWatch custom metrics for security and operational monitoring. 
The Terraform module (`terraform-aws-jumphost`) has already provisioned the necessary IAM permissions 
and CloudWatch infrastructure; Puppet's responsibility is to configure the CloudWatch agent 
and custom metric collection scripts.

**Key Deliverables**:
1. CloudWatch agent configuration with procstat and disk metrics
2. Custom script for AuditEventsLost and FailedLogins metrics
3. Puppet manifest updates for jumphost role
4. Testing and validation in development environment
5. Documentation updates

---

## Implementation Approach

### Architecture Decision: Hybrid Approach

We'll use a **hybrid approach** combining native CloudWatch agent features with custom scripts:

| Metric | Collection Method | Rationale |
|--------|------------------|-----------|
| **ServiceStatus** | CloudWatch agent `procstat` plugin | Native support, reliable process monitoring |
| **DiskSpaceUsed** | CloudWatch agent `disk` plugin | Native support, standard filesystem metrics |
| **AuditEventsLost** | Custom script → AWS CLI PutMetricData | Requires parsing `auditctl -s` output |
| **FailedLogins** | Custom script → AWS CLI PutMetricData | Requires parsing auth logs |

**Why not StatsD?**
- Adds complexity with minimal benefit for only 2 custom metrics
- AWS CLI approach is simpler, more maintainable, and already available
- StatsD would require additional agent configuration and debugging

### File Structure

```
environments/development/modules/profile/
├── manifests/
│   └── jumphost/
│       ├── cloudwatch_agent.pp          # Main manifest (already exists, needs extension)
│       └── cloudwatch_metrics.pp        # New: Custom metrics configuration
├── templates/
│   └── jumphost/
│       ├── amazon-cloudwatch-agent.json.erb   # Existing: Extend for metrics
│       └── publish-jumphost-metrics.sh.erb    # New: Custom metrics script
└── files/
    └── jumphost/
        └── (none needed)
```

### Puppet Fact Usage

The Terraform module provides these facts via cloud-init:
```puppet
$facts['hostname']                          # Route53 hostname (e.g., "jumphost") - for log groups only
$facts['environment']                       # Environment (e.g., "production")
$facts['jumphost']['cloudwatch_log_group']  # Log group name
```

**CRITICAL - Hostname for Metrics** (Requirements v1.1):
- **For CloudWatch metric dimensions**: Use EC2 instance hostname via `$facts['networking']['hostname']` (e.g., `ip-10-0-1-5`)
- **Rationale**: Jumphosts use NLB with Auto Scaling Group; metrics are instance-level
- **DO NOT use**: Route53 hostname (`$facts['hostname']`) or EC2 instance ID for metric dimensions

```puppet
$ec2_hostname = $facts['networking']['hostname']  # e.g., "ip-10-0-1-5" - USE THIS FOR METRICS
```

---

## Task Breakdown

### Phase 1: Development Setup and Configuration

#### Task 1.1: Extend CloudWatch Agent Configuration
- **File**: `environments/development/modules/profile/templates/jumphost/amazon-cloudwatch-agent.json.erb`
- **Status**: ✅ Complete (Superseded by custom metrics approach)
- **Owner**: Claude Code
- **Actual Time**: 2 hours
- **Dependencies**: None

**What Was Done**:
- [x] Extended CloudWatch agent configuration with metrics section
- [x] Configured `procstat` plugin to monitor `auditd` process
- [x] Configured `disk` plugin for root filesystem
- [x] Set namespace to `Jumphost/System`
- [x] Set `omit_hostname: true` to prevent conflicting dimensions
- [x] Configured `append_dimensions` with `Hostname` and `Environment`

**⚠️ Implementation Change**:
CloudWatch agent's `append_dimensions` feature does not work reliably - metrics were published without the custom dimensions.

**Decision**: Pivoted to **custom metrics approach** (Tasks 1.2-1.3) using `aws cloudwatch put-metric-data` for full control over metric names and dimensions. This approach successfully publishes all 4 metrics with correct dimensions.

**CloudWatch agent still used for**: Log shipping (existing functionality preserved)

**Validation**: ✅ Passed - Agent config valid, logs shipping correctly

---

#### Task 1.2: Create Custom Metrics Collection Script
- **File**: `environments/development/modules/profile/templates/jumphost/publish-jumphost-metrics.sh.erb`
- **Status**: ✅ Complete
- **Owner**: Claude Code
- **Actual Time**: 3 hours
- **Dependencies**: None

**Requirements**:
- [x] Create bash script template using Puppet facts for dimensions
- [x] Implement **ServiceStatus** metric (added - uses `pidof auditd`)
- [x] Implement **DiskSpaceUsed** metric (added - uses `df -h /`)
- [x] Implement **AuditEventsLost** metric (uses `auditctl -s` with delta calculation)
- [x] Implement **FailedLogins** metric (uses `journalctl` with timestamp tracking)
- [x] Set proper error handling (`set -euo pipefail`)
- [x] AWS region auto-detected from EC2 metadata facts
- [x] Correct namespace (`Jumphost/System`) and dimensions (Hostname, Environment)
- [x] State directory `/var/run/jumphost-metrics` for delta tracking

**✅ All 4 metrics implemented** in single script for simplicity

**Script Template Structure**:
```bash
#!/bin/bash
set -euo pipefail

# Configuration from Puppet facts
# CRITICAL: Use EC2 instance hostname, not Route53 hostname
HOSTNAME="<%= @ec2_hostname %>"  # e.g., "ip-10-0-1-5"
ENVIRONMENT="<%= @environment %>"
REGION="us-west-1"  # Or: $(ec2-metadata --availability-zone | sed 's/[a-z]$//')
NAMESPACE="Jumphost/System"

# State files
AUDIT_LOST_FILE="/var/run/jumphost-audit-lost.count"
FAILED_LOGIN_TS_FILE="/var/run/jumphost-failed-logins.timestamp"

# Function: publish_metric
publish_metric() {
  local metric_name=$1
  local value=$2
  local unit=$3

  aws cloudwatch put-metric-data \
    --namespace "$NAMESPACE" \
    --metric-name "$metric_name" \
    --value "$value" \
    --unit "$unit" \
    --dimensions Hostname="$HOSTNAME",Environment="$ENVIRONMENT" \
    --region "$REGION"
}

# Metric 1: AuditEventsLost
# ... implementation ...

# Metric 2: FailedLogins
# ... implementation ...

logger -t jumphost-metrics "Published metrics: AuditEventsLost=$DELTA_LOST, FailedLogins=$FAILED_COUNT"
```

**Reference**: See requirements doc section "Custom Metrics: AuditEventsLost and FailedLogins" (lines 275-353)

**Validation**:
```bash
# Test script execution
sudo /usr/local/bin/publish-jumphost-metrics.sh
# Check syslog output
tail -f /var/log/syslog | grep jumphost-metrics
```

---

#### Task 1.3: Create Puppet Manifest for Custom Metrics
- **File**: `environments/development/modules/profile/manifests/jumphost/custom_metrics.pp`
- **Status**: ✅ Complete
- **Owner**: Claude Code
- **Actual Time**: 1 hour
- **Dependencies**: Task 1.2

**Requirements**:
- [x] Create new Puppet class `profile::jumphost::custom_metrics`
- [x] Deploy custom metrics script to `/usr/local/bin/publish-jumphost-metrics`
  - Mode: `0755` (executable)
  - Owner: `root`
  - Content: From template `jumphost/publish-jumphost-metrics.sh.erb`
- [x] Create cron job to run script every minute
- [x] Ensure `awscli` package is installed
- [x] Auto-detect AWS region from EC2 metadata facts
- [x] Extract short hostname from networking facts

**Puppet Manifest Structure**:
```puppet
class profile::jumphost::cloudwatch_metrics {
  # Ensure AWS CLI is installed
  package { 'awscli':
    ensure => installed,
  }

  # Deploy custom metrics collection script
  file { '/usr/local/bin/publish-jumphost-metrics.sh':
    ensure  => file,
    mode    => '0755',
    owner   => 'root',
    group   => 'root',
    content => template('profile/jumphost/publish-jumphost-metrics.sh.erb'),
  }

  # Cron job to run metrics collection every minute
  cron { 'publish-jumphost-metrics':
    command => '/usr/local/bin/publish-jumphost-metrics.sh > /dev/null 2>&1',
    user    => 'root',
    minute  => '*',
    require => File['/usr/local/bin/publish-jumphost-metrics.sh'],
  }
}
```

**Validation**:
```bash
# Check cron job
crontab -l | grep publish-jumphost-metrics
# Verify script exists and is executable
ls -la /usr/local/bin/publish-jumphost-metrics.sh
```

---

#### Task 1.4: Update CloudWatch Agent Manifest
- **File**: `environments/development/modules/profile/manifests/jumphost/cloudwatch_agent.pp`
- **Status**: ✅ Complete
- **Owner**: Claude Code
- **Actual Time**: 30 minutes
- **Dependencies**: Task 1.1

**Requirements**:
- [x] Added service restart notification when config file changes
- [x] Fixed service restart dependencies

**Note**: Template variables (`$ec2_hostname`, `$environment`) are set in custom_metrics.pp manifest instead since we pivoted to custom metrics approach.

**Changes Required**:
```puppet
# In profile::jumphost::cloudwatch_agent
# Add variables for template (CRITICAL)
$ec2_hostname = $facts['networking']['hostname']  # e.g., "ip-10-0-1-5"
$environment = $facts['environment']               # e.g., "development"

file { '/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json':
  ensure  => file,
  content => template('profile/jumphost/amazon-cloudwatch-agent.json.erb'),
  require => Package['amazon-cloudwatch-agent'],
  notify  => Exec['restart-cloudwatch-agent'],
}

exec { 'restart-cloudwatch-agent':
  command     => '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                  -a fetch-config -m ec2 \
                  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s',
  refreshonly => true,
  path        => ['/bin', '/usr/bin'],
}
```

**Validation**:
```bash
# Check agent status
systemctl status amazon-cloudwatch-agent
# Verify config is loaded
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a query -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
```

---

#### Task 1.5: Integrate into Jumphost Role
- **File**: `environments/development/data/jumphost.yaml`
- **Status**: ✅ Complete
- **Owner**: Claude Code
- **Actual Time**: 10 minutes
- **Dependencies**: Task 1.3

**Requirements**:
- [x] Added `profile::jumphost::custom_metrics` to classes array in Hiera
- [x] Positioned after `profile::jumphost::cloudwatch_agent`
- [x] No circular dependencies

**Hiera Configuration**:
```yaml
# environments/development/data/jumphost.yaml
classes:
  - profile::jumphost
  - profile::jumphost::auditd
  - profile::jumphost::cloudwatch_agent
  - profile::jumphost::cloudwatch_metrics  # <-- Add this
```

**Validation**:
```bash
# On jumphost, verify class is included
puppet apply --test --noop
```

---

### Phase 2: Testing and Validation

#### Task 2.1: Deploy to Development Jumphost
- **Status**: ✅ Complete
- **Owner**: User
- **Actual Time**: 1 hour
- **Dependencies**: All Phase 1 tasks

**Requirements**:
- [x] Build and publish Puppet package to development APT repository
- [x] SSH to development jumphost instance
- [x] Update puppet-code package: `sudo apt-get update && sudo apt-get install puppet-code`
- [x] Run Puppet apply: `sudo ih-puppet apply`
- [x] Check for Puppet errors in output
- [x] Verify all files are deployed correctly:
  - `/etc/aws/amazon-cloudwatch-agent.json` ✓
  - `/usr/local/bin/publish-jumphost-metrics` ✓
- [x] Verify services are running:
  - `systemctl status amazon-cloudwatch-agent` ✓
  - `systemctl status auditd` ✓
- [x] Check cron job is created: `crontab -l` ✓

**Validation Results**:
- ✅ No Puppet errors during apply
- ✅ All files deployed with correct permissions
- ✅ CloudWatch agent running (version 1.300057.1b1167)
- ✅ Auditd running (no lost events)
- ✅ Cron job configured (runs every minute)
- ✅ Configuration validated (JSON syntax correct)
- ✅ Metrics publishing to CloudWatch (ServiceStatus, DiskSpaceUsed)

---

#### Task 2.2: Verify Metric Publication
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 1.5 hours
- **Dependencies**: Task 2.1

**Requirements**:
- [ ] Wait 5-10 minutes for metrics to be published
- [ ] Check CloudWatch agent logs for errors:
  - `/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log`
- [ ] Manually run custom metrics script and check for errors:
  - `sudo /usr/local/bin/publish-jumphost-metrics.sh`
  - Check syslog: `tail -f /var/log/syslog | grep jumphost-metrics`
- [ ] Verify metrics appear in AWS CloudWatch console:
  - Navigate to CloudWatch → Metrics
  - Select namespace: `Jumphost/System`
  - Verify dimensions: `Hostname=<ec2-instance-hostname>`, `Environment=development`
    - **Note**: Hostname will be EC2 instance hostname (e.g., `ip-10-0-1-5`), NOT `jumphost`
  - Check all 4 metrics exist:
    - ServiceStatus (should be 1 if auditd running)
    - DiskSpaceUsed (should show percentage)
    - AuditEventsLost (may be 0 if no events lost)
    - FailedLogins (may be 0 if no failed logins)
- [ ] Use AWS CLI to query metrics (replace `ip-10-0-1-5` with actual EC2 hostname):
```bash
# First, get the actual EC2 hostname
HOSTNAME=$(hostname)
echo "EC2 Hostname: $HOSTNAME"

aws cloudwatch get-metric-statistics \
  --namespace Jumphost/System \
  --metric-name ServiceStatus \
  --dimensions Name=Hostname,Value=$HOSTNAME Name=Environment,Value=development \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average
```

**Success Criteria**:
- All 4 metrics appear in CloudWatch console within 10 minutes
- Dimensions match exactly: `Hostname=<ec2-instance-hostname>`, `Environment=development`
  - **CRITICAL**: Hostname dimension will be EC2 instance hostname (e.g., `ip-10-0-1-5`), NOT `jumphost`
- ServiceStatus = 1 (auditd is running)
- DiskSpaceUsed shows realistic percentage (e.g., 15-40%)
- No errors in CloudWatch agent logs
- No errors in syslog from custom metrics script

**Troubleshooting**:
If metrics don't appear:
- Check IAM instance profile permissions
- Verify namespace is exactly `Jumphost/System`
- Check dimension names (case-sensitive)
- Review CloudWatch agent logs for errors
- Test manual metric publication with AWS CLI

---

#### Task 2.3: Trigger Test Scenarios
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 2 hours
- **Dependencies**: Task 2.2

**Requirements**:

**Test Scenario 1: ServiceStatus (Auditd Down)**
- [ ] Stop auditd: `sudo systemctl stop auditd`
- [ ] Wait 2 minutes for CloudWatch agent to detect
- [ ] Verify `ServiceStatus` metric goes to 0 in CloudWatch console
- [ ] Start auditd: `sudo systemctl start auditd`
- [ ] Verify metric returns to 1

**Test Scenario 2: AuditEventsLost**
- [ ] Trigger audit event loss (stress test audit system):
  - Generate high-volume audit events
  - Or manually increment lost counter for testing
- [ ] Run custom metrics script: `sudo /usr/local/bin/publish-jumphost-metrics.sh`
- [ ] Verify `AuditEventsLost` metric appears with delta value
- [ ] Check syslog for metric publication confirmation

**Test Scenario 3: FailedLogins**
- [ ] Generate failed SSH login attempts:
  ```bash
  # From another machine
  ssh invalid_user@jumphost  # Enter wrong password 3 times
  ```
- [ ] Wait 1 minute for cron to run custom metrics script
- [ ] Verify `FailedLogins` metric shows count of failures
- [ ] Check syslog: `grep "jumphost-metrics" /var/log/syslog`

**Test Scenario 4: DiskSpaceUsed**
- [ ] Verify metric shows current disk usage
- [ ] Optional: Create large file to increase usage, verify metric updates
- [ ] Remove test file

**Success Criteria**:
- All metrics respond to actual system changes
- Metrics appear in CloudWatch within expected timeframes
- Delta calculations work correctly (AuditEventsLost, FailedLogins)
- No false positives or negatives

---

#### Task 2.4: Code Quality and Linting
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 30 minutes
- **Dependencies**: All Phase 1 tasks

**Requirements**:
- [ ] Run puppet-lint on all modified manifests:
```bash
puppet-lint --fail-on-warnings environments/development/modules/profile/manifests/jumphost/cloudwatch_agent.pp
puppet-lint --fail-on-warnings environments/development/modules/profile/manifests/jumphost/cloudwatch_metrics.pp
```
- [ ] Fix any linting warnings or errors
- [ ] Run shellcheck on custom metrics script:
```bash
shellcheck environments/development/modules/profile/templates/jumphost/publish-jumphost-metrics.sh.erb
```
- [ ] Fix any shell script issues
- [ ] Validate JSON template syntax:
```bash
# Extract ERB to temp file and validate (manual check)
```
- [ ] Ensure templates use proper ERB syntax and escaping

**Success Criteria**:
- Zero puppet-lint warnings
- Zero shellcheck errors
- JSON template is valid when rendered
- Pre-commit hook passes

---

### Phase 3: Multi-Environment Deployment

#### Task 3.1: Extend to Sandbox Environment
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 2 hours
- **Dependencies**: All Phase 2 tasks

**Requirements**:
- [ ] Copy configuration to sandbox environment:
  - `environments/sandbox/modules/profile/manifests/jumphost/cloudwatch_metrics.pp`
  - `environments/sandbox/modules/profile/templates/jumphost/amazon-cloudwatch-agent.json.erb`
  - `environments/sandbox/modules/profile/templates/jumphost/publish-jumphost-metrics.sh.erb`
- [ ] Update sandbox Hiera data: `environments/sandbox/data/jumphost.yaml`
- [ ] Deploy to sandbox jumphost
- [ ] Verify metrics appear with `Environment=sandbox` dimension
- [ ] Spot-check all 4 metrics in CloudWatch console

**Notes**:
- Sandbox and development configurations should be identical
- Only dimension values will differ (Environment=sandbox vs development)

---

#### Task 3.2: Extend to Production Environment
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 2 hours
- **Dependencies**: Task 3.1

**Requirements**:
- [ ] Copy configuration to production environment (via shared modules):
  - Update `modules/profile/manifests/jumphost/cloudwatch_metrics.pp` (shared)
  - Update `modules/profile/templates/jumphost/amazon-cloudwatch-agent.json.erb` (shared)
  - Update `modules/profile/templates/jumphost/publish-jumphost-metrics.sh.erb` (shared)
- [ ] Update production Hiera data if jumphost exists
- [ ] Coordinate with ops team for production deployment window
- [ ] Deploy to production jumphost
- [ ] Monitor for 24 hours
- [ ] Verify metrics appear with `Environment=production` dimension
- [ ] Check for any errors in logs

**Pre-Production Checklist**:
- [ ] All development and sandbox tests passed
- [ ] No linting errors
- [ ] Code review completed
- [ ] Deployment runbook prepared
- [ ] Rollback plan ready

**Rollback Plan**:
- Remove `profile::jumphost::cloudwatch_metrics` from Hiera
- Run Puppet apply to remove cron job and script
- Metrics will stop publishing but logs continue working

---

### Phase 4: Terraform Integration and Alarms

#### Task 4.1: Coordinate with Terraform Team
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 1 hour
- **Dependencies**: Task 3.2

**Requirements**:
- [ ] Notify Terraform module maintainers that metrics are live
- [ ] Provide confirmation that all 4 metrics are publishing correctly
- [ ] Share metric schema and dimension naming:
  - Namespace: `Jumphost/System`
  - Dimensions: `Hostname` (EC2 instance hostname like `ip-10-0-1-5`), `Environment`
  - Metric names: `ServiceStatus`, `AuditEventsLost`, `DiskSpaceUsed`, `FailedLogins`
  - **CRITICAL**: Hostname dimension uses EC2 instance hostname, NOT Route53 name
- [ ] Request that they enable alarms: `enable_audit_alarms = true`
- [ ] Coordinate testing of alarm triggers

**Deliverables**:
- Email or Slack message to Terraform team
- Metric schema documentation
- Screenshots of metrics in CloudWatch console (optional)

---

#### Task 4.2: Validate Alarms (with Terraform Team)
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 2 hours
- **Dependencies**: Task 4.1, Terraform team enables alarms

**Requirements**:
- [ ] Verify alarms are created in AWS CloudWatch console
- [ ] Test alarm triggers in development:
  - Stop auditd → ServiceStatus alarm
  - Generate failed logins → FailedLogins alarm
  - (AuditEventsLost and DiskSpaceUsed harder to trigger safely)
- [ ] Verify alarm notifications work (SNS topic, email, etc.)
- [ ] Document alarm response procedures
- [ ] Create runbook for on-call team

**Success Criteria**:
- Alarms trigger within expected timeframes (5 minutes for ServiceStatus)
- Notifications are received by appropriate teams
- Alarms clear when conditions resolve

---

### Phase 5: Documentation and Knowledge Transfer

#### Task 5.1: Update Puppet Documentation
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 1 hour
- **Dependencies**: Task 3.2

**Requirements**:
- [ ] Create/update README: `environments/development/modules/profile/README-jumphost-metrics.md`
- [ ] Document what metrics are published
- [ ] Document configuration files and templates
- [ ] Document troubleshooting steps
- [ ] Add examples of how to query metrics with AWS CLI
- [ ] Include links to requirements document

**Content Outline**:
```markdown
# Jumphost CloudWatch Metrics

## Overview
This profile configures CloudWatch custom metrics for security and operational monitoring of jumphosts.

## Metrics Published
- ServiceStatus: Auditd process health (0 or 1)
- AuditEventsLost: Audit events lost due to buffer overflow
- DiskSpaceUsed: Root filesystem usage (percentage)
- FailedLogins: SSH authentication failures

## Configuration Files
- Manifest: profile::jumphost::cloudwatch_metrics
- Template: jumphost/amazon-cloudwatch-agent.json.erb
- Template: jumphost/publish-jumphost-metrics.sh.erb

## Troubleshooting
...
```

---

#### Task 5.2: Update CLAUDE.md (if needed)
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 30 minutes
- **Dependencies**: Task 5.1

**Requirements**:
- [ ] Add entry for `profile::jumphost::cloudwatch_metrics` to common profiles section
- [ ] Update jumphost role description to mention metrics monitoring
- [ ] Document that metrics require Terraform module v2.x+ (check version)

---

#### Task 5.3: Knowledge Transfer
- **Status**: ⬜ Not Started
- **Owner**: TBD
- **Estimated Time**: 1 hour
- **Dependencies**: All tasks

**Requirements**:
- [ ] Schedule walkthrough with ops team
- [ ] Demo metrics in CloudWatch console
- [ ] Review troubleshooting procedures
- [ ] Share runbook for alarm responses
- [ ] Answer questions

---

## Testing Checklist

Use this checklist during Phase 2 testing:

### Pre-Deployment Checks
- [ ] Puppet lint passes with no warnings
- [ ] Shellcheck passes on custom metrics script
- [ ] JSON template renders valid JSON
- [ ] All templates use correct Puppet facts
- [ ] Namespace is exactly `Jumphost/System`
- [ ] Dimensions use `Hostname` and `Environment` (case-sensitive)

### Post-Deployment Checks (Development)
- [ ] Puppet apply completes without errors
- [ ] CloudWatch agent service is running
- [ ] Auditd service is running
- [ ] Custom metrics script is deployed to `/usr/local/bin/`
- [ ] Cron job exists and runs every minute
- [ ] CloudWatch agent logs show no errors
- [ ] Syslog shows metric publication messages

### Metrics Validation (Development)
- [ ] ServiceStatus metric appears in CloudWatch (value = 1)
- [ ] DiskSpaceUsed metric appears (value = realistic percentage)
- [ ] AuditEventsLost metric can be triggered
- [ ] FailedLogins metric can be triggered
- [ ] All metrics have correct dimensions: `Hostname=<ec2-instance-hostname>`, `Environment=development`
  - **Note**: Use EC2 hostname (e.g., `ip-10-0-1-5`), NOT Route53 name
- [ ] All metrics use namespace: `Jumphost/System`

### Integration Tests
- [ ] Stop/start auditd → ServiceStatus changes
- [ ] Failed SSH login → FailedLogins increments
- [ ] Metrics persist after instance reboot
- [ ] Metrics work on fresh jumphost instance

### Multi-Environment Checks
- [ ] Sandbox metrics appear with `Environment=sandbox`
- [ ] Production metrics appear with `Environment=production`
- [ ] Multiple jumphosts in same environment have unique `Hostname` dimensions (each EC2 instance has unique hostname)

---

## Rollout Strategy

### Development (Week 1)
- Implement all configuration (Tasks 1.1 - 1.5)
- Deploy and test (Tasks 2.1 - 2.4)
- Fix any issues found

### Sandbox (Week 2)
- Deploy to sandbox environment (Task 3.1)
- Validate metrics for 2-3 days
- Ensure no impact on existing jumphost functionality

### Production (Week 3)
- Deploy to production during maintenance window (Task 3.2)
- Monitor closely for 24 hours
- Enable alarms after confirming metrics are stable (Task 4.1)

### Post-Production (Week 4)
- Validate alarms (Task 4.2)
- Complete documentation (Tasks 5.1 - 5.3)
- Close out project

---

## Risk Mitigation

### Risk 1: CloudWatch Agent Configuration Breaks Existing Logs
- **Likelihood**: Low
- **Impact**: High
- **Mitigation**:
  - Preserve existing `logs` configuration when adding `metrics` section
  - Test logs still ship to CloudWatch after deployment
  - Keep backup of working configuration

### Risk 2: Custom Script Causes High CPU/Memory Usage
- **Likelihood**: Low
- **Impact**: Medium
- **Mitigation**:
  - Script runs once per minute (60 second intervals)
  - Use efficient parsing (grep, awk, not heavy processing)
  - Monitor jumphost resource usage during testing

### Risk 3: IAM Permissions Insufficient
- **Likelihood**: Very Low (Terraform already provisioned)
- **Impact**: High
- **Mitigation**:
  - Terraform module already grants `cloudwatch:PutMetricData`
  - Test manual metric publication before deploying
  - Verify IAM permissions in development first

### Risk 4: Metrics Don't Match Alarm Dimensions
- **Likelihood**: Medium
- **Impact**: High (alarms won't work)
- **Mitigation**:
  - Use exact dimension names from requirements doc
  - Test with Terraform team before production
  - Coordinate namespace and dimension naming

### Risk 5: Audit Log Parsing Misses Events
- **Likelihood**: Medium
- **Impact**: Low (metrics are best-effort)
- **Mitigation**:
  - Use `journalctl` when available (more reliable)
  - Fallback to auth.log parsing
  - Monitor false negatives in development

---

## Success Metrics

### Technical Success
- [ ] All 4 metrics publish successfully to CloudWatch
- [ ] Metrics appear within expected timeframes (1-5 minutes)
- [ ] Dimensions match Terraform alarm expectations
- [ ] Zero Puppet errors during deployment
- [ ] Zero CloudWatch agent errors after deployment

### Operational Success
- [ ] Alarms trigger correctly when thresholds are breached
- [ ] No false positives from alarms
- [ ] Ops team can troubleshoot using CloudWatch console
- [ ] Metrics provide actionable insights

### Quality Success
- [ ] Code passes all linting checks
- [ ] Documentation is complete and accurate
- [ ] Knowledge transfer completed
- [ ] Runbooks created for on-call team

---

## Timeline Summary

| Phase | Duration | Key Milestones |
|-------|----------|----------------|
| Phase 1: Development Setup | 2-3 days | All manifests and templates created |
| Phase 2: Testing | 1-2 days | Metrics validated in development |
| Phase 3: Multi-Environment | 2-3 days | Sandbox and production deployed |
| Phase 4: Terraform Integration | 1 day | Alarms enabled and tested |
| Phase 5: Documentation | 1 day | Knowledge transfer complete |
| **Total** | **7-10 days** | Project complete |

---

## Open Questions

1. **AWS Region**: Should we auto-detect region from EC2 metadata or hardcode to `us-west-1`?
   - **Recommendation**: Auto-detect for flexibility

2. **Error Handling**: What should happen if `auditctl` command is unavailable?
   - **Recommendation**: Log error to syslog, skip metric publication, don't fail script

3. **State Files**: Where should we store state files for delta calculations?
   - **Current Plan**: `/var/run/jumphost-*.count` (tmpfs, cleared on reboot)
   - **Alternative**: `/var/lib/jumphost/metrics/` (persistent across reboots)
   - **Recommendation**: Use `/var/run/` for simplicity, acceptable to reset deltas on reboot

4. **Metric Units**: Requirements specify `None` for ServiceStatus - confirm this is correct (not `Count`)?
   - **Answer**: Yes, `None` is correct for binary status metrics (0 or 1)

5. **Failed Login Detection**: Should we count only password failures or all auth failures (e.g., key-based)?
   - **Recommendation**: Start with password failures only, expand if needed

---

## Dependencies

### External Dependencies
- Terraform module `terraform-aws-jumphost` v2.x+ (provides IAM permissions)
- CloudWatch log groups already created
- Jumphost instances must have IAM instance profile attached

### Package Dependencies
- `amazon-cloudwatch-agent` - CloudWatch agent package
- `awscli` - AWS CLI for metric publication
- `auditd` - Audit daemon (should already be installed)

### Puppet Dependencies
- `profile::jumphost::auditd` - Ensures auditd is configured
- `profile::jumphost::cloudwatch_agent` - Base CloudWatch agent setup

---

## Appendix: File Checklist

### New Files to Create
- [ ] `environments/development/modules/profile/manifests/jumphost/cloudwatch_metrics.pp`
- [ ] `environments/development/modules/profile/templates/jumphost/publish-jumphost-metrics.sh.erb`
- [ ] `environments/development/modules/profile/README-jumphost-metrics.md`

### Files to Modify
- [ ] `environments/development/modules/profile/templates/jumphost/amazon-cloudwatch-agent.json.erb`
- [ ] `environments/development/modules/profile/manifests/jumphost/cloudwatch_agent.pp`
- [ ] `environments/development/data/jumphost.yaml`

### Files to Copy to Other Environments
- [ ] Sandbox environment (3 files)
- [ ] Production environment (via shared modules)

---

## Contact and Support

**Puppet Module Maintainers**: TBD
**Terraform Module Maintainers**: TBD
**On-Call Team**: TBD

**Related Documentation**:
- [Requirements Document](./puppet-cloudwatch-metrics-requirements.md)
- [Terraform Module Docs](https://github.com/infrahouse/terraform-aws-jumphost)
- [CloudWatch Agent Docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html)

---

**Document Version**: 1.1
**Last Updated**: 2025-12-19
**Status**: Ready for Implementation
**Change Log**: Updated to use EC2 instance hostname instead of Route53 hostname for metric dimensions (requirements v1.1)
