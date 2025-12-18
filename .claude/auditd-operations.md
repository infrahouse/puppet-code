# Auditd Operations Runbook

## Quick Reference

### Health Check (30 seconds)
```bash
# 1. Check service
sudo systemctl status auditd

# 2. Check for lost events (should be 0)
sudo auditctl -s | grep lost

# 3. Check disk space
sudo df -h /var/log/audit/

# 4. Recent errors
sudo journalctl -u auditd --since "5 minutes ago" | grep -i error
```

### Emergency Contacts
- **Security Team**: security@infrahouse.com
- **On-Call**: [PagerDuty/Opsgenie]
- **Compliance**: compliance@infrahouse.com

---

## Alert Response Procedures

### Alert: Audit Event Loss

**Severity**: HIGH
**Impact**: Compliance violation, potential blind spots in security monitoring

#### Symptoms
- CloudWatch alert: "Audit events lost"
- `auditctl -s` shows `lost > 0`
- Kernel logs: "audit: rate limit exceeded"

#### Immediate Actions
```bash
# 1. Check current loss
sudo auditctl -s | grep lost

# 2. Check buffer status
sudo auditctl -s | grep backlog

# 3. Check kernel messages
sudo dmesg | grep audit | tail -20

# 4. Identify event rate
sudo aureport | head -20
```

#### Resolution
```bash
# Emergency: Stop noisy process if identified
sudo systemctl stop <noisy-service>

# Check Puppet-managed config
cat /etc/audit/rules.d/00-base.rules | grep -E "^-b|^-r"

# Should show:
# -b 65536 (backlog)
# -r 0 (rate limit - unlimited)

# If values are wrong, trigger Puppet run
sudo /usr/local/bin/puppet_apply.sh

# Verify fix
sudo augenrules --load
sudo auditctl -s | grep -E "rate_limit|backlog_limit"
```

#### Escalation
- If lost events > 10,000: Notify Security Team
- If persistent after fix: Page On-Call
- If compliance deadline affected: Notify Compliance Team

---

### Alert: Auditd Service Down

**Severity**: CRITICAL
**Impact**: No audit logging, compliance violation

#### Immediate Actions
```bash
# 1. Check service status
sudo systemctl status auditd

# 2. View recent logs
sudo journalctl -u auditd -n 50

# 3. Check configuration
sudo auditd -t

# 4. Restart service
sudo systemctl restart auditd

# 5. Verify rules loaded
sudo auditctl -l | wc -l
# Should be 100+ rules
```

#### Common Causes

**Invalid Configuration**
```bash
# Check for syntax errors
sudo journalctl -u auditd | grep -i "unknown keyword\|invalid\|error"

# Recent Puppet changes?
sudo grep -r "auditd" /opt/puppet-code/environments/*/modules/profile/
```

**Disk Full**
```bash
# Check disk space
df -h /var/log/audit/

# Emergency: Clear old logs
sudo logrotate -f /etc/logrotate.d/audit

# Or manually remove oldest
sudo rm /var/log/audit/audit.log.10
```

**Permissions Issue**
```bash
# Check log directory
ls -la /var/log/audit/

# Fix permissions
sudo chown root:root /var/log/audit/
sudo chmod 0750 /var/log/audit/
```

#### Escalation
- If cannot restart within 5 minutes: Page On-Call
- If configuration issue: Contact DevOps Team
- Document in incident report for compliance

---

### Alert: High Disk Usage (/var/log/audit/)

**Severity**: MEDIUM
**Impact**: Risk of disk full, service disruption

#### Immediate Actions
```bash
# 1. Check disk usage
sudo du -sh /var/log/audit/
df -h /var/log/audit/

# 2. Check log rotation
ls -lh /var/log/audit/

# 3. Trigger rotation
sudo logrotate -f /etc/logrotate.d/audit

# 4. Verify space freed
df -h /var/log/audit/
```

#### If Still Critical (>90% full)
```bash
# Check for abnormal log growth
sudo stat /var/log/audit/audit.log

# If file is huge (>500MB), investigate
sudo aureport | head -30

# Archive old logs to S3 (if approved)
for log in /var/log/audit/audit.log.{5..10}; do
    aws s3 cp "$log" s3://compliance-audit-logs/$(hostname)/ \
        && sudo rm "$log"
done
```

#### Prevention
- Verify logrotate config: `/etc/logrotate.d/audit`
- Check CloudWatch agent is shipping logs
- Review audit rules for excessive events

---

## Common Operational Tasks

### Investigate Security Incident

#### User Activity Investigation
```bash
# 1. Find user ID
id <username>

# 2. All actions by user
sudo ausearch -ui <uid> -ts yesterday

# 3. Sudo commands
sudo ausearch -ui <uid> -k sudo_commands

# 4. File access
sudo ausearch -ui <uid> -k file_deletion

# 5. SSH sessions
sudo ausearch -ui <uid> -m USER_LOGIN
```

#### Unauthorized Access Investigation
```bash
# 1. Failed login attempts
sudo aureport -au --failed --summary

# 2. Successful logins
sudo aureport -au --success -ts yesterday

# 3. Root access
sudo ausearch -ui 0 -ts yesterday

# 4. Privilege escalation
sudo ausearch -k privilege_escalation -k sudo_commands
```

#### File Tampering Investigation
```bash
# 1. Changes to specific file
sudo ausearch -f /etc/passwd

# 2. All security file changes
sudo ausearch -k passwd_changes -k shadow_changes -k group_changes

# 3. SSH key modifications
sudo ausearch -k ssh_keys

# 4. Sudo config changes
sudo ausearch -k sudoers_changes
```

### Generate Compliance Reports

#### Monthly SOC2 Report
```bash
# Create report directory
REPORT_DIR="/tmp/audit-report-$(date +%Y-%m)"
mkdir -p "$REPORT_DIR"

# Generate reports
sudo aureport --start $(date -d "1 month ago" +%m/%d/%Y) > "$REPORT_DIR/summary.txt"
sudo aureport -au --start $(date -d "1 month ago" +%m/%d/%Y) > "$REPORT_DIR/authentication.txt"
sudo aureport -m --start $(date -d "1 month ago" +%m/%d/%Y) > "$REPORT_DIR/modifications.txt"
sudo aureport -x --start $(date -d "1 month ago" +%m/%d/%Y) > "$REPORT_DIR/commands.txt"

# Archive
tar -czf "$REPORT_DIR.tar.gz" "$REPORT_DIR"

# Upload to S3
aws s3 cp "$REPORT_DIR.tar.gz" s3://compliance-reports/audit/
```

#### Audit Status Report
```bash
# System audit health
cat << EOF > /tmp/audit-status.txt
=== Audit System Status ===
Date: $(date)
Hostname: $(hostname)

Service Status:
$(sudo systemctl status auditd | head -5)

Event Statistics:
$(sudo auditctl -s)

Recent Activity (24h):
$(sudo aureport --start today)

Lost Events: $(sudo auditctl -s | grep lost | awk '{print $2}')

Rules Count: $(sudo auditctl -l | wc -l)
EOF

cat /tmp/audit-status.txt
```

### Add Custom Audit Rule (Temporary)

```bash
# Add file watch
sudo auditctl -w /path/to/file -p rwxa -k custom_watch

# Add syscall rule
sudo auditctl -a always,exit -F arch=b64 -S open -k custom_syscall

# Verify rule added
sudo auditctl -l | grep custom

# Note: Temporary rules are lost on reboot
# To make permanent, add to Puppet templates
```

### Troubleshoot CloudWatch Integration

```bash
# 1. Check agent status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a query -m ec2 -c default

# 2. Check config
sudo cat /etc/aws/amazon-cloudwatch-agent.json | jq .

# 3. Check permissions (cwagent user)
sudo -u cwagent cat /var/log/audit/audit.log | head -5

# 4. Check ACL
getfacl /var/log/audit/ | grep cwagent

# 5. View agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# 6. Restart agent
sudo systemctl restart amazon-cloudwatch-agent
```

---

## Maintenance Procedures

### Weekly Health Check

```bash
#!/bin/bash
# Save as: /usr/local/bin/audit-health-check.sh

echo "=== Weekly Audit Health Check ==="
echo "Date: $(date)"
echo

# Service status
echo "Service Status:"
systemctl is-active auditd && echo "✓ auditd running" || echo "✗ auditd NOT running"
echo

# Lost events
LOST=$(sudo auditctl -s | grep lost | awk '{print $2}')
echo "Lost Events: $LOST"
if [ "$LOST" -gt 0 ]; then
    echo "⚠ WARNING: Events have been lost!"
fi
echo

# Disk usage
echo "Disk Usage:"
du -sh /var/log/audit/
df -h /var/log/audit/ | tail -1
echo

# Rule count
RULES=$(sudo auditctl -l | wc -l)
echo "Active Rules: $RULES"
if [ "$RULES" -lt 50 ]; then
    echo "⚠ WARNING: Rule count is low!"
fi
echo

# Recent activity
echo "Recent Activity (last hour):"
sudo ausearch -ts recent 2>/dev/null | wc -l
echo "events"
```

### Monthly Tasks

1. **Generate compliance report** (see above)
2. **Review alert history** - Check for recurring issues
3. **Audit rule review** - Ensure rules still relevant
4. **Performance check** - Review CPU/disk usage trends
5. **Log archive** - Verify old logs archived to S3

### Quarterly Tasks

1. **Compliance audit** - Work with security team
2. **Rule optimization** - Remove noisy/unused rules
3. **Documentation update** - Update runbook if needed
4. **Disaster recovery test** - Verify log restoration

---

## Emergency Procedures

### Disable Auditd (Emergency Only)

⚠️ **WARNING**: Only use in emergency (system instability, critical performance issue)

```bash
# 1. Document reason
echo "$(date): Disabling auditd - Reason: <YOUR REASON>" | \
    sudo tee -a /var/log/audit-emergency.log

# 2. Stop service
sudo systemctl stop auditd

# 3. Prevent auto-start
sudo systemctl mask auditd

# 4. Notify security team immediately
# Email security@infrahouse.com with:
# - Hostname
# - Timestamp
# - Reason for disabling
# - Expected duration

# 5. Create incident ticket
```

### Re-enable After Emergency

```bash
# 1. Unmask service
sudo systemctl unmask auditd

# 2. Start service
sudo systemctl start auditd

# 3. Verify rules loaded
sudo auditctl -l | wc -l

# 4. Document resolution
echo "$(date): Re-enabled auditd" | \
    sudo tee -a /var/log/audit-emergency.log

# 5. Update incident ticket
```

---

## Performance Tuning

### High Event Rate

If experiencing >1000 events/second:

```bash
# 1. Identify noisy rules
sudo aureport --event | head -20

# 2. Check for problematic syscalls
sudo auditctl -l | grep -E "setuid|setgid|execve"

# 3. Increase buffer (emergency)
sudo auditctl -b 131072

# 4. For permanent fix, update Puppet:
# Edit: environments/*/modules/profile/templates/auditd/base.rules.erb
# Increase: -b 131072
```

### Reduce Noise

```bash
# Common noisy patterns to exclude:

# Exclude specific user (e.g., monitoring)
-a never,exit -F auid=<monitoring_uid>

# Exclude specific process
-a never,exit -F exe=/usr/bin/cron

# Exclude success-only events for noisy operations
-a always,exit -F arch=b64 -S open -F success=0
```

---

## Known Issues

### Issue: Rules Not Persistent After Reboot

**Cause**: Rules added with `auditctl` are temporary

**Fix**: All rules must be in Puppet templates:
- `base.rules.erb` - Base rules
- `compliance.rules.erb` - Compliance rules
- `<role>.rules.erb` - Role-specific rules

### Issue: "audit: backlog limit exceeded"

**Cause**: Buffer too small for event rate

**Fix**: Already fixed in `base.rules.erb` with `-b 65536`

### Issue: CloudWatch Agent Can't Read Logs

**Cause**: ACL permissions not set

**Fix**: Puppet manages this in `cloudwatch_agent.pp`:
```bash
setfacl -R -m u:cwagent:r-x /var/log/audit/
```

---

## Monitoring and Alerts

### Recommended CloudWatch Alarms

1. **Audit Service Down**
   - Metric: ServiceStatus
   - Threshold: < 1 for 5 minutes
   - Action: Page on-call

2. **Event Loss**
   - Metric: AuditEventsLost
   - Threshold: > 0
   - Action: Alert security team

3. **High Disk Usage**
   - Metric: DiskSpaceUsed
   - Threshold: > 90%
   - Action: Alert ops team

4. **Failed Login Attempts**
   - Metric: FailedLogins
   - Threshold: > 10 in 5 minutes
   - Action: Alert security team

---

## References

- Developer Documentation: `environments/development/modules/profile/README-auditd.md`
- Compliance Rollout Plan: `.claude/plans/compliance-logging-rollout.md`
- Puppet Code: `modules/profile/manifests/auditd.pp`
- [Red Hat Audit Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/chap-system_auditing)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)

---

## Appendix: Quick Command Reference

```bash
# Status and health
sudo systemctl status auditd
sudo auditctl -s
sudo auditctl -l

# Search logs
sudo ausearch -ts recent
sudo ausearch -k <key>
sudo ausearch -ui <uid>
sudo ausearch -f <file>

# Reports
sudo aureport
sudo aureport -au
sudo aureport --summary

# Real-time
sudo tail -f /var/log/audit/audit.log
sudo ausearch -ts recent | tail -f

# Maintenance
sudo augenrules --load
sudo systemctl restart auditd
sudo logrotate -f /etc/logrotate.d/audit

# Troubleshooting
sudo journalctl -u auditd
sudo dmesg | grep audit
sudo auditctl -s | grep lost
```