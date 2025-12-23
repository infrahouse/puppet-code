# CloudWatch Logging Standardization Plan

## Task Tracker

| Phase | Task | Status    |
|-------|------|-----------|
| 1 | Fix logrotate ACL persistence | ✅ Done    |
| 2 | Remove btmp/wtmp from jumphost config | ✅ Done    |
| 2 | Remove utmp group from cwagent user | ✅ Done |
| 2 | Remove duplicate DiskSpaceUsed metric | ✅ Done    |
| 2 | Propagate Phase 2 to sandbox environment | ✅ Done |
| 2 | Propagate Phase 2 to development environment | ✅ Done |
| 3 | Create shared base class `profile::cloudwatch_agent` | ⬜ Pending |
| 3 | Create shared ACL scripts | ⬜ Pending |
| 4 | Upgrade OpenVPN CloudWatch manifest | ⬜ Pending |
| 4 | Upgrade OpenVPN CloudWatch template | ⬜ Pending |
| 5 | Update jumphost to use shared base | ⬜ Pending |
| 5 | Delete old jumphost ACL scripts | ⬜ Pending |
| 6 | Create OpenVPN auditd profile | ⬜ Pending |
| 6 | Include auditd in openvpn_server.pp | ⬜ Pending |
| - | Run puppet-lint validation | ⬜ Pending |

## Overview

Standardize CloudWatch logging across EC2 services (jumphost, openvpn_server) with consistent, secure, 
and SOC2/ISO27001 compliant patterns.

## Issues to Fix


### 1. Audit Log Permission Denied (Critical) ✅ FIXED
- **Problem**: Logrotate creates new `audit.log` with `create 0640 root root` but no ACLs
- **Impact**: CloudWatch agent loses access after log rotation
- **Fix**: Add postrotate ACL reapplication in logrotate config
- **Status**: Fixed in commit `43fc19a` (PR #215)

### 2. Binary Log Files (btmp/wtmp)
- **Problem**: Binary files that CloudWatch agent can't parse
- **Impact**: Missing streams `auth/successful-logins`, garbled data in `auth/failed-logins`
- **Fix**: Remove from CloudWatch config, remove `utmp` group from cwagent user

### 3. Inconsistent Implementations
- **Problem**: OpenVPN has weaker security/logging than jumphost
- **Fix**: Upgrade OpenVPN to match jumphost pattern

## Implementation Plan

### Phase 1: Fix Logrotate ACL Persistence

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

### Phase 2: Remove Binary Log Files

**File**: `modules/profile/templates/jumphost/amazon-cloudwatch-agent.json.erb`

Remove entries for:
- `/var/log/btmp` (failed-logins)
- `/var/log/wtmp` (successful-logins)

**File**: `modules/profile/manifests/jumphost/cloudwatch_agent.pp`

Change cwagent groups from `['adm', 'utmp']` to `['adm']`

### Phase 3: Create Shared Base Class

**New File**: `modules/profile/manifests/cloudwatch_agent.pp`

Shared resources:
- Package `acl`
- Script `/usr/local/bin/set-audit-acl`
- Script `/usr/local/bin/check-audit-acl`

**New Files**:
- `modules/profile/templates/cloudwatch_agent/set-audit-acl.sh.erb`
- `modules/profile/templates/cloudwatch_agent/check-audit-acl.sh.erb`

### Phase 4: Standardize OpenVPN CloudWatch Agent

**File**: `modules/profile/manifests/openvpn_server/cloudwatch_agent.pp`

Changes:
1. Include `profile::cloudwatch_agent` base class
2. Add cwagent user with `['adm']` group
3. Fix config file permissions: `0644` -> `0640`
4. Add ACL exec for audit log access
5. Add health check cron (every 5 min)
6. Add monitoring script `/usr/local/bin/check-cloudwatch-agent`

**File**: `modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb`

Changes:
1. Add agent section (`run_as_user: cwagent`, `buffer_time: 10000`)
2. Add `timezone: UTC` to all log entries
3. Standardize log stream naming (hierarchical: `{instance_id}/category/type`)
4. Add audit.log collection
5. Add dpkg.log for package tracking
6. Add metrics section (CPU, disk, memory, swap, procstat for openvpn)
7. Add dimensions (Hostname, Environment)

### Phase 5: Update Jumphost to Use Shared Base

**File**: `modules/profile/manifests/jumphost/cloudwatch_agent.pp`

Changes:
1. Include `profile::cloudwatch_agent` base class
2. Remove duplicate ACL package/script resources
3. Update ACL exec to depend on shared class

**Files to Delete**:
- `modules/profile/templates/jumphost/set-audit-acl.sh.erb`
- `modules/profile/templates/jumphost/check-audit-acl.sh.erb`

### Phase 6: Add OpenVPN Auditd Profile

**New File**: `modules/profile/manifests/openvpn_server/auditd.pp`

Include base `profile::auditd` and optionally add OpenVPN-specific rules.

**File**: `modules/profile/manifests/openvpn_server.pp`

Add: `include 'profile::openvpn_server::auditd'`

## File Summary

### Create:
| File | Purpose |
|------|---------|
| `modules/profile/manifests/cloudwatch_agent.pp` | Shared base class |
| `modules/profile/templates/cloudwatch_agent/set-audit-acl.sh.erb` | Shared ACL script |
| `modules/profile/templates/cloudwatch_agent/check-audit-acl.sh.erb` | Shared ACL check |
| `modules/profile/manifests/openvpn_server/auditd.pp` | OpenVPN auditd config |

### Modify:
| File | Changes |
|------|---------|
| `modules/profile/templates/auditd/logrotate.erb` | ✅ Already done (PR #215) |
| `modules/profile/templates/jumphost/amazon-cloudwatch-agent.json.erb` | Remove btmp/wtmp |
| `modules/profile/manifests/jumphost/cloudwatch_agent.pp` | Use shared base, remove utmp |
| `modules/profile/manifests/openvpn_server/cloudwatch_agent.pp` | Full upgrade |
| `modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb` | Add agent/metrics/timezone |
| `modules/profile/manifests/openvpn_server.pp` | Include auditd |

### Delete:
| File | Reason |
|------|---------|
| `modules/profile/templates/jumphost/set-audit-acl.sh.erb` | Moved to shared |
| `modules/profile/templates/jumphost/check-audit-acl.sh.erb` | Moved to shared |

## Environment Propagation

After changes to `modules/profile/`:
1. Copy to `environments/sandbox/modules/profile/`
2. Copy to `environments/development/modules/profile/`

## Testing

```bash
# Puppet lint
puppet-lint --fail-on-warnings modules/profile

# Verify ACL persistence
sudo logrotate -f /etc/logrotate.d/audit
getfacl /var/log/audit/audit.log
sudo -u cwagent cat /var/log/audit/audit.log | head

# Verify CloudWatch agent
/usr/local/bin/check-cloudwatch-agent
```

## Namespace Defaults

If Terraform doesn't provide `cloudwatch_namespace` fact, Puppet will use defaults:

**In manifest** (`openvpn_server/cloudwatch_agent.pp`):
```puppet
$cloudwatch_namespace = pick($facts['openvpn']['cloudwatch_namespace'], 'InfraHouse/OpenVPN')
```

**In manifest** (`jumphost/cloudwatch_agent.pp`):
```puppet
$cloudwatch_namespace = pick($facts['jumphost']['cloudwatch_namespace'], 'InfraHouse/Jumphost')
```

This ensures metrics always work, with sensible defaults that Terraform can override.

## Rollout

1. **Sandbox** - Deploy, test for 48-72 hours
2. **Development** - Deploy, test for 48-72 hours
3. **Production** - Deploy during maintenance window
