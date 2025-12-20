# Auditd Profile Documentation

## Overview

The `profile::auditd` provides comprehensive system auditing for SOC2/ISO27001 compliance. It configures the Linux audit framework (auditd) to capture security-relevant events.

## Files

```
manifests/
├── auditd.pp                    # Base auditd profile (all systems)
└── jumphost/
    ├── auditd.pp                # Jumphost-specific audit rules
    └── cloudwatch_agent.pp      # CloudWatch Logs integration

templates/auditd/
├── auditd.conf.erb              # Daemon configuration
├── base.rules.erb               # Base audit rules (all systems)
├── compliance.rules.erb         # SOC2/ISO27001 compliance rules
└── logrotate.erb                # Log rotation configuration

templates/jumphost/
├── jumphost.rules.erb           # Jumphost-specific rules
└── amazon-cloudwatch-agent.json.erb  # CloudWatch config
```

## Configuration

### Buffer and Rate Limits
Configured in `base.rules.erb`:
- **Backlog buffer**: 65536 (handles traffic spikes)
- **Rate limit**: 0 (unlimited, prevents event loss)

### Log Files
- Primary log: `/var/log/audit/audit.log`
- Format: enriched (more detail for compliance)
- Rotation: 10 files × 50MB each
- Permissions: 0640 (readable by root and cwagent)

---

## Common Commands

### Check Auditd Status
```bash
# Service status
sudo systemctl status auditd

# Detailed status
sudo auditctl -s

# Expected output:
# enabled 1
# failure 1
# pid 1234
# rate_limit 0
# backlog_limit 65536
# lost 0              # Should be 0!
# backlog 0
```

### View Current Audit Rules
```bash
# List all active rules
sudo auditctl -l

# Count rules
sudo auditctl -l | wc -l

# Search for specific rules
sudo auditctl -l | grep ssh
sudo auditctl -l | grep sudo
```

### Search Audit Logs

#### Recent Events
```bash
# Last 10 minutes
sudo ausearch -ts recent

# Last hour
sudo ausearch -ts today

# Specific time range
sudo ausearch -ts 18:00 -te 19:00
```

#### By Event Type
```bash
# SSH logins
sudo ausearch -m USER_LOGIN

# Authentication failures
sudo ausearch -m USER_AUTH -sv no

# Sudo commands
sudo ausearch -m USER_CMD

# File access
sudo ausearch -f /etc/passwd

# User activity
sudo ausearch -ua <username>
```

#### By Key (Rule Tags)
```bash
# View all keys
sudo auditctl -l | grep -o "key=[^ ]*" | sort -u

# Search by key
sudo ausearch -k passwd_changes
sudo ausearch -k ssh_keys
sudo ausearch -k sudoers_changes
sudo ausearch -k audit_logs
```

### Generate Reports
```bash
# Summary of all events
sudo aureport

# Authentication report
sudo aureport -au

# Failed authentication attempts
sudo aureport -au --failed

# File access report
sudo aureport -f

# User command report
sudo aureport -x

# Summary by user
sudo aureport -u --summary

# Time range reports
sudo aureport -ts today -te now
```

### Real-time Monitoring
```bash
# Watch audit log in real-time
sudo tail -f /var/log/audit/audit.log

# Follow with filtering
sudo ausearch -ts recent | tail -f

# Watch specific events
sudo ausearch -m USER_LOGIN --start recent --format text -i | tail -f
```

### Reload Configuration
```bash
# Reload rules without restarting (preferred)
sudo augenrules --load

# Restart service (if config changed)
sudo systemctl restart auditd

# Verify rules loaded
sudo auditctl -l
```

### Check for Event Loss
```bash
# Check kernel for lost events
sudo auditctl -s | grep lost

# Search logs for rate limit messages
sudo dmesg | grep -i audit
sudo journalctl -u auditd | grep -i "rate limit\|lost"

# If lost > 0, increase buffer or disable rate limit in base.rules.erb
```

---

## Testing Audit Rules

### Generate Test Events
```bash
# File access
sudo cat /etc/shadow

# Password change
sudo passwd testuser

# Sudo execution
sudo ls /root

# SSH key access
sudo cat /root/.ssh/authorized_keys

# File deletion
rm /tmp/test-file
```

### Verify Events Captured
```bash
# Check if event was logged
sudo ausearch -ts recent -k passwd_changes
sudo ausearch -ts recent -k ssh_keys
sudo ausearch -ts recent -k sudo_commands
```

---

## Troubleshooting

### Auditd Won't Start
```bash
# Check configuration syntax
sudo auditd -t

# View detailed error
sudo journalctl -u auditd -n 50

# Common issues:
# - Invalid keyword in auditd.conf
# - Conflicting rules in *.rules files
# - Permissions on /var/log/audit/
```

### Rules Not Loading
```bash
# Check for syntax errors
sudo augenrules --check

# View loaded rules
sudo augenrules --load

# Check rule files
ls -la /etc/audit/rules.d/
```

### High CPU Usage
```bash
# Check event rate
sudo auditctl -s | grep -E "rate_limit|backlog"

# Identify noisy rules
sudo aureport | grep -A 10 "Event type"

# Common culprits:
# - setuid/setgid syscalls (200+ events/sec)
# - execve syscalls (50+ events/min)
# - Wide directory watches (/usr/bin/, /usr/sbin/)
```

### Disk Space Issues
```bash
# Check audit log size
sudo du -sh /var/log/audit/

# Check rotation status
ls -lh /var/log/audit/

# Force rotation
sudo logrotate -f /etc/logrotate.d/audit
```

---

## CloudWatch Integration

### Check CloudWatch Agent
```bash
# Agent status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2 -c default

# View agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Check log streaming
aws logs tail /aws/ec2/jumphost --follow
```

### Verify Log Permissions
```bash
# Check ACL on audit logs
getfacl /var/log/audit/

# Should show: user:cwagent:r-x
# If not, Puppet will set it via cloudwatch_agent.pp
```

---

## Performance Monitoring

### Event Rate
```bash
# Count events in last minute
sudo ausearch -ts recent | wc -l

# Monitor event rate
watch -n 1 'sudo auditctl -s | grep -E "rate_limit|backlog|lost"'
```

### System Impact
```bash
# Check auditd CPU/memory
ps aux | grep auditd

# Monitor system load
top -p $(pgrep auditd)
```

---

## Compliance Queries

### SOC2 Requirements

#### Access Control (CC6.1)
```bash
# User account changes
sudo ausearch -k passwd_changes -k group_changes

# Privilege escalation
sudo ausearch -k sudo_commands

# Authentication events
sudo aureport -au
```

#### Monitoring (CC7.2)
```bash
# System file modifications
sudo ausearch -k system_config

# Security configuration changes
sudo ausearch -k audit_config -k auth_config
```

#### Change Management (CC8.1)
```bash
# System changes
sudo ausearch -k system_config -k init_config

# Network changes
sudo ausearch -k network_config
```

### ISO27001 Requirements

#### A.12.4.1 - Event Logging
```bash
# All logged events
sudo aureport --summary

# Authentication attempts
sudo aureport -au
```

#### A.12.4.3 - Administrator Logs
```bash
# Root actions
sudo ausearch -ui 0

# Sudo usage
sudo ausearch -k sudo_commands
```

---

## References

- [Audit Rules Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-defining_audit_rules_and_controls)
- [Auditd Configuration Guide](https://linux.die.net/man/8/auditd.conf)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- Compliance Rollout Plan: `.claude/plans/compliance-logging-rollout.md`

---

## Related Puppet Classes

- `profile::auditd` - Base audit configuration (all systems)
- `profile::jumphost::auditd` - Jumphost-specific rules
- `profile::jumphost::cloudwatch_agent` - CloudWatch Logs integration