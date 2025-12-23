# CloudWatch Logging Standardization Plan

## Task Tracker

| Phase | Task | Status    |
|-------|------|-----------|
| 1 | Fix logrotate ACL persistence | ✅ Done    |
| 2 | Remove btmp/wtmp from jumphost config | ✅ Done    |
| 2 | Remove utmp group from cwagent user | ✅ Done |
| 2 | Remove duplicate DiskSpaceUsed metric | ✅ Done    |
| 3 | Create shared base class in development | ⬜ Pending |
| 3 | Create shared ACL scripts in development | ⬜ Pending |
| 4 | Update jumphost to use shared base (development) | ⬜ Pending |
| 4 | Delete old jumphost ACL scripts (development) | ⬜ Pending |
| 5 | Upgrade OpenVPN CloudWatch (development) | ⬜ Pending |
| 5 | Add OpenVPN auditd profile (development) | ⬜ Pending |
| 6 | Run puppet-lint validation | ⬜ Pending |
| 6 | Create PR | ⬜ Pending |
| 7 | Test in development (Jumphost + OpenVPN) | ⬜ Pending |
| 8 | Promote to sandbox environment | ⬜ Pending |
| 8 | Test in sandbox | ⬜ Pending |
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

### Phase 3: Create Shared Base Class (Development)

**IMPORTANT**: All changes in phases 3-5 are made in `environments/development/modules/profile/` ONLY.

**New File**: `environments/development/modules/profile/manifests/cloudwatch_agent.pp`

Shared resources:
- Package `acl`
- Script `/usr/local/bin/set-audit-acl`
- Script `/usr/local/bin/check-audit-acl`

**New Files**:
- `environments/development/modules/profile/templates/cloudwatch_agent/set-audit-acl.sh.erb`
- `environments/development/modules/profile/templates/cloudwatch_agent/check-audit-acl.sh.erb`

### Phase 4: Update Jumphost to Use Shared Base (Development)

**File**: `environments/development/modules/profile/manifests/jumphost/cloudwatch_agent.pp`

Changes:
1. Include `profile::cloudwatch_agent` base class
2. Remove duplicate ACL package/script resources
3. Update ACL exec to depend on shared class

**Files to Delete**:
- `environments/development/modules/profile/templates/jumphost/set-audit-acl.sh.erb`
- `environments/development/modules/profile/templates/jumphost/check-audit-acl.sh.erb`

### Phase 5: Standardize OpenVPN CloudWatch Agent (Development)

**File**: `environments/development/modules/profile/manifests/openvpn_server/cloudwatch_agent.pp`

Changes:
1. Include `profile::cloudwatch_agent` base class
2. Add cwagent user with `['adm']` group
3. Fix config file permissions: `0644` -> `0640`
4. Add ACL exec for audit log access
5. Add health check cron (every 5 min)
6. Add monitoring script `/usr/local/bin/check-cloudwatch-agent`

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

1. **Development** - Implement, create PR, merge, test on Jumphost + OpenVPN
2. **Sandbox** - Promote changes, test for 48-72 hours
3. **Production** - Promote to global `modules/profile/`
