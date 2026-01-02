# CloudWatch Logging Standardization Plan

## Task Tracker

| Phase | Task | Status    |
|-------|------|-----------|
| 1 | Fix logrotate ACL persistence | ✅ Done    |
| 2 | Remove btmp/wtmp from jumphost config | ✅ Done    |
| 2 | Remove utmp group from cwagent user | ✅ Done |
| 2 | Remove duplicate DiskSpaceUsed metric | ✅ Done    |
| 3 | Create shared base class in development | ✅ Done |
| 3 | Create shared ACL scripts in development | ✅ Done |
| 4 | Update jumphost to use shared base (development) | ✅ Done |
| 4 | Delete old jumphost ACL scripts (development) | ✅ Done |
| 5 | Upgrade OpenVPN CloudWatch (development) | ✅ Done |
| 5 | Add OpenVPN auditd profile (development) | ✅ Done |
| 6 | Run puppet-lint validation | ✅ Done |
| 6 | Create PR | ✅ Done |
| 7 | Test in development (Jumphost + OpenVPN) | ✅ Done |
| 8 | Promote to sandbox environment | ✅ Done |
| 8 | Test in sandbox | ✅ Done |
| 9 | Promote to global modules/profile | ⬜ Pending |

## Overview

Standardize CloudWatch logging across EC2 services (jumphost, openvpn_server) with consistent, secure, 
and SOC2/ISO27001 compliant patterns.

## Issues to Fix


### 1. Audit Log Permission Denied (Critical) ✅ FIXED
- **Problem**: Logrotate creates new `audit.log` with `create 0640 root root` but no ACLs
- **Impact**: CloudWatch agent loses access after log rotation
- **Fix**: Add postrotate ACL reapplication in logrotate config
- **Status**: Fixed in commit `43fc19a` (PR #215)

### 2. Binary Log Files (btmp/wtmp) ✅ FIXED
- **Problem**: Binary files that CloudWatch agent can't parse
- **Impact**: Missing streams `auth/successful-logins`, garbled data in `auth/failed-logins`
- **Fix**: Remove from CloudWatch config, remove `utmp` group from cwagent user
- **Status**: Fixed in PR #216

### 3. Inconsistent Implementations
- **Problem**: OpenVPN has weaker security/logging than jumphost
- **Fix**: Upgrade OpenVPN to match jumphost pattern

## Implementation Plan

### Phase 1: Fix Logrotate ACL Persistence ✅ DONE

**File**: `modules/profile/templates/auditd/logrotate.erb`

Add postrotate ACL reapplication:
```erb
postrotate
    /usr/sbin/service auditd rotate
    # Reapply ACLs for CloudWatch agent access
    if [ -x /usr/local/bin/set-audit-acl ]; then
        /usr/local/bin/set-audit-acl
    fi
endscript
```

 ### Phase 2: Remove Binary Log Files ✅ DONE

**File**: `modules/profile/templates/jumphost/amazon-cloudwatch-agent.json.erb`

Remove entries for:
- `/var/log/btmp` (failed-logins)
- `/var/log/wtmp` (successful-logins)

**File**: `modules/profile/manifests/jumphost/cloudwatch_agent.pp`

Change cwagent groups from `['adm', 'utmp']` to `['adm']`

### Phase 3: Create Shared Base Class (Development) ✅ DONE

**IMPORTANT**: All changes in phases 3-5 are made in `environments/development/modules/profile/` ONLY.

**New File**: `environments/development/modules/profile/manifests/cloudwatch_agent.pp`

Shared resources:
- Package `acl`
- Script `/usr/local/bin/set-audit-acl`
- Script `/usr/local/bin/check-audit-acl`

**New Files**:
- `environments/development/modules/profile/templates/cloudwatch_agent/set-audit-acl.sh.erb`
- `environments/development/modules/profile/templates/cloudwatch_agent/check-audit-acl.sh.erb`

### Phase 4: Update Jumphost to Use Shared Base (Development) ✅ DONE

**File**: `environments/development/modules/profile/manifests/jumphost/cloudwatch_agent.pp`

Changes:
1. Include `profile::cloudwatch_agent` base class
2. Remove duplicate ACL package/script resources
3. Update ACL exec to depend on shared class

**Files to Delete**:
- `environments/development/modules/profile/templates/jumphost/set-audit-acl.sh.erb`
- `environments/development/modules/profile/templates/jumphost/check-audit-acl.sh.erb`

### Phase 5: Standardize OpenVPN CloudWatch Agent (Development) ✅ DONE

**File**: `environments/development/modules/profile/manifests/openvpn_server/cloudwatch_agent.pp`

Changes:
1. Include `profile::cloudwatch_agent` base class
2. Add cwagent user with `['adm']` group
3. Fix config file permissions: `0644` -> `0640`
4. Add ACL exec for audit log access
5. Add monitoring script `/usr/local/bin/check-cloudwatch-agent`
6. Remove `-s` flag from exec, let systemd manage restarts

**File**: `environments/development/modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb`

Changes:
1. Add agent section (`run_as_user: cwagent`, `buffer_time: 10000`)
2. Add `timezone: UTC` to all log entries
3. Standardize log stream naming (hierarchical: `{instance_id}/category/type`)
4. Add audit.log collection
5. Add dpkg.log for package tracking
6. Add metrics section (CPU, disk, memory, swap, procstat for openvpn)
7. Add dimensions (Hostname, Environment)

**New File**: `environments/development/modules/profile/manifests/openvpn_server/auditd.pp`

Include base `profile::auditd` and optionally add OpenVPN-specific rules.

**File**: `environments/development/modules/profile/manifests/openvpn_server.pp`

Add: `include 'profile::openvpn_server::auditd'`

### Phase 6: Validate and Create PR

1. Run puppet-lint validation on development environment
2. Create pull request with all development changes

### Phase 7: Test in Development Environment

After PR is merged:
1. Test on development Jumphost - verify CloudWatch agent, logs, metrics
2. Test on development OpenVPN - verify CloudWatch agent, logs, metrics

### Phase 8: Promote to Sandbox Environment

After successful development testing:
1. Copy changes from `environments/development/modules/profile/` to `environments/sandbox/modules/profile/`
2. Test on sandbox Jumphost and OpenVPN
3. Create PR for sandbox changes

### Phase 9: Promote to Global Modules

After successful sandbox testing:
1. Copy changes from `environments/sandbox/modules/profile/` to `modules/profile/`
2. Create PR for production changes

## File Summary (Development Environment)

### Create:
| File | Purpose |
|------|---------|
| `environments/development/modules/profile/manifests/cloudwatch_agent.pp` | Shared base class |
| `environments/development/modules/profile/templates/cloudwatch_agent/set-audit-acl.sh.erb` | Shared ACL script |
| `environments/development/modules/profile/templates/cloudwatch_agent/check-audit-acl.sh.erb` | Shared ACL check |
| `environments/development/modules/profile/manifests/openvpn_server/auditd.pp` | OpenVPN auditd config |

### Modify:
| File | Changes |
|------|---------|
| `environments/development/modules/profile/manifests/jumphost/cloudwatch_agent.pp` | Use shared base |
| `environments/development/modules/profile/manifests/openvpn_server/cloudwatch_agent.pp` | Full upgrade |
| `environments/development/modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb` | Add agent/metrics/timezone |
| `environments/development/modules/profile/manifests/openvpn_server.pp` | Include auditd |

### Delete:
| File | Reason |
|------|---------|
| `environments/development/modules/profile/templates/jumphost/set-audit-acl.sh.erb` | Moved to shared |
| `environments/development/modules/profile/templates/jumphost/check-audit-acl.sh.erb` | Moved to shared |

## Testing

```bash
# Puppet lint (development environment)
puppet-lint --fail-on-warnings environments/development/modules/profile

# On development Jumphost/OpenVPN:
# Verify ACL persistence
sudo logrotate -f /etc/logrotate.d/audit
getfacl /var/log/audit/audit.log
sudo -u cwagent cat /var/log/audit/audit.log | head

# Verify CloudWatch agent groups
cat /proc/$(pgrep -f amazon-cloudwatch)/status | grep Groups

# Verify CloudWatch agent status
/usr/local/bin/check-cloudwatch-agent
```

## CloudWatch Namespace Convention

### Pattern: `<Service>/<Component>`

**Format:** `{ServiceName}/{Component}`

**Examples:**
- `Jumphost/System` - System metrics for jumphost servers
- `OpenVPN/System` - System metrics for OpenVPN servers
- `Elasticsearch/System` - System metrics for Elasticsearch nodes

**Components:**
- `System` - OS-level metrics (CPU, memory, disk, network)
- `Application` - Application-specific metrics (future use)

**Distinguishing multiple instances:**
Use CloudWatch dimensions, not namespaces:
- `host` - EC2 hostname (built-in)
- `environment` - dev/sandbox/production

### Defaults in Puppet

If Terraform doesn't provide `cloudwatch_namespace` fact, Puppet uses these defaults:

**In manifest** (`openvpn_server/cloudwatch_agent.pp`):
```puppet
$cloudwatch_namespace = pick($facts['openvpn']['cloudwatch_namespace'], 'OpenVPN/System')
```

**In manifest** (`jumphost/cloudwatch_agent.pp`):
```puppet
$cloudwatch_namespace = pick($facts['jumphost']['cloudwatch_namespace'], 'Jumphost/System')
```

This ensures metrics always work, with sensible defaults that Terraform can override.

## CloudWatch Metrics Specification

### Dimension Standard

All metrics use these dimensions:

| Dimension | Source | Description |
|-----------|--------|-------------|
| `host` | CloudWatch agent built-in | EC2 instance hostname |
| `environment` | Puppet `$environment` | dev/sandbox/production |

Additional dimensions added automatically by metric type:
- `cpu` for CPU metrics
- `path`, `device`, `fstype` for disk metrics
- `name` for diskio metrics
- `pattern`, `pid_finder` for procstat metrics

### Common Metrics (All Services)

Collected by CloudWatch agent. Namespace: `<Service>/System`

#### CPU Metrics
| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `CPU_IDLE` | Percent | 60s | CPU idle time |
| `CPU_IOWAIT` | Percent | 60s | CPU waiting for I/O |
| `CPU_USER` | Percent | 60s | CPU in user mode |
| `CPU_SYSTEM` | Percent | 60s | CPU in kernel mode |

#### Memory Metrics
| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `MEM_USED_PERCENT` | Percent | 60s | Memory utilization |
| `MEM_AVAILABLE` | Bytes | 60s | Available memory |
| `SWAP_USED_PERCENT` | Percent | 60s | Swap utilization |

#### Disk Metrics
| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `DISK_USED_PERCENT` | Percent | 300s | Filesystem usage (root only) |
| `DISK_INODES_FREE` | Count | 300s | Free inodes (root only) |

#### Disk I/O Metrics
| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `DISKIO_TIME` | Milliseconds | 60s | Time spent on I/O |
| `DISKIO_READ_BYTES` | Bytes | 60s | Bytes read |
| `DISKIO_WRITE_BYTES` | Bytes | 60s | Bytes written |

**Note**: diskio collects for all devices. Consider filtering to `nvme*` only if noise is a concern.

#### Network Metrics
| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `TCP_ESTABLISHED` | Count | 60s | Established TCP connections |
| `TCP_TIME_WAIT` | Count | 60s | Connections in TIME_WAIT |
| `TCP_LISTEN` | Count | 60s | Listening sockets |

#### Process Metrics
| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `PROCESSES_RUNNING` | Count | 60s | Running processes |
| `PROCESSES_SLEEPING` | Count | 60s | Sleeping processes |
| `PROCESSES_ZOMBIES` | Count | 60s | Zombie processes |

#### Process Monitoring (procstat)
| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `procstat_lookup_pid_count` | Count | 60s | Process count for pattern |

Patterns monitored:
- `auditd` - All services (security requirement)
- `openvpn` - OpenVPN only

### Jumphost-Specific Metrics

Collected by custom script (`/usr/local/bin/publish-jumphost-metrics`).
Namespace: `Jumphost/System`

| Metric | Unit | Interval | Description |
|--------|------|----------|-------------|
| `ServiceStatus` | None | 60s | auditd running (1) or not (0) |
| `AuditEventsLost` | Count | 60s | Delta of lost audit events |
| `FailedLogins` | Count | 60s | SSH authentication failures (from journalctl) |

**Note**: `ServiceStatus` overlaps with `procstat_lookup_pid_count` (pattern=auditd). Consider consolidating in future.

### OpenVPN-Specific Metrics

Currently only uses common metrics. Future additions:
- VPN connection count
- Bandwidth per client
- Certificate expiration

### Metrics NOT Collected

| Metric | Reason |
|--------|--------|
| `net` (network interfaces) | Low value, high cardinality |
| `ethtool` | Not needed for cloud instances |
| Per-CPU metrics | `totalcpu: false` aggregates to single value |

## CloudWatch Logs Specification

### Log Stream Naming

Pattern: `{instance_id}/<category>/<type>`

| Category | Type | Log File |
|----------|------|----------|
| `audit` | `security` | `/var/log/audit/audit.log` |
| `auth` | `ssh` | `/var/log/auth.log` |
| `system` | `syslog` | `/var/log/syslog` |
| `system` | `kernel` | `/var/log/kern.log` |
| `system` | `packages` | `/var/log/dpkg.log` |
| `security` | `fail2ban` | `/var/log/fail2ban.log` (Jumphost) |
| `openvpn` | `server` | `/var/log/openvpn/openvpn.log` (OpenVPN) |
| `cloudwatch` | `agent` | CloudWatch agent logs |

### Common Logs (All Services)

- `/var/log/audit/audit.log` - Security audit trail
- `/var/log/auth.log` - Authentication events
- `/var/log/syslog` - System messages
- `/var/log/kern.log` - Kernel messages
- `/var/log/dpkg.log` - Package changes
- CloudWatch agent logs

### Service-Specific Logs

**Jumphost:**
- `/var/log/fail2ban.log` - Intrusion prevention

**OpenVPN:**
- `/var/log/openvpn/openvpn.log` - VPN server logs

### Logs NOT Collected

| Log | Reason |
|-----|--------|
| `/var/log/btmp` | Binary file, can't parse |
| `/var/log/wtmp` | Binary file, can't parse |
| `/var/log/openvpn/openvpn-status.log` | Status file, not a log (rewritten, not appended) |
| `/var/log/dmesg` | One-time boot log, kern.log has same info |

## Rollout

1. **Development** - Implement, create PR, merge, test on Jumphost + OpenVPN
2. **Sandbox** - Promote changes, test for 48-72 hours
3. **Production** - Promote to global `modules/profile/`
