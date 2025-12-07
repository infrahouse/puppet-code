# Task: Add CloudWatch Logs Agent Support to Puppet OpenVPN Server Role

## Task Progress

**Status**: 🟡 In Progress
**Branch**: `feature/cloudwatch-agent-openvpn`
**Started**: 2025-12-07

### Checklist

**Phase 1: Development Environment** (Current Release)
- [x] Create feature branch
- [x] Implement CloudWatch agent support in `development` environment
  - [x] Create `environments/development/modules/profile/manifests/openvpn_server/cloudwatch_agent.pp`
  - [x] Create `environments/development/modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb`
  - [x] Update `environments/development/modules/profile/manifests/openvpn_server.pp`
  - [x] Pass puppet-lint validation
- [x] Test implementation on development OpenVPN instance
  - [x] Verify service starts and runs
  - [x] Verify logs appear in CloudWatch
  - [x] Run Terraform pytest: `test_cloudwatch_logging()` - ✅ PASSED
- [ ] Create pull request for Phase 1
- [ ] Merge Phase 1 to main
- [ ] Deploy and monitor in development

**Phase 2: Sandbox Environment** (Next Release)
- [ ] Create new feature branch for Phase 2
- [ ] Implement in `sandbox` environment
  - [ ] Copy/adapt `environments/sandbox/modules/profile/manifests/openvpn_server/cloudwatch_agent.pp`
  - [ ] Copy/adapt `environments/sandbox/modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb`
  - [ ] Update `environments/sandbox/modules/profile/manifests/openvpn_server.pp`
- [ ] Test on sandbox OpenVPN instance
- [ ] Create pull request for Phase 2
- [ ] Merge Phase 2 to main
- [ ] Deploy and monitor in sandbox

**Phase 3: Production & Global Modules** (Final Release)
- [ ] Create new feature branch for Phase 3
- [ ] Promote to global `modules/profile`
  - [ ] Create `modules/profile/manifests/openvpn_server/cloudwatch_agent.pp`
  - [ ] Create `modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb`
  - [ ] Update `modules/profile/manifests/openvpn_server.pp`
- [ ] Remove environment-specific overrides from development and sandbox
- [ ] Test on production OpenVPN instance
- [ ] Create pull request for Phase 3
- [ ] Merge Phase 3 to main
- [ ] Deploy and monitor in production

### Implementation Summary

**Files Created**:
- ✅ `environments/development/modules/profile/manifests/openvpn_server/cloudwatch_agent.pp`
- ✅ `environments/development/modules/profile/templates/openvpn_server/amazon-cloudwatch-agent.json.erb`

**Files Modified**:
- ✅ `environments/development/modules/profile/manifests/openvpn_server.pp`

**Implementation Approach**:
- **Puppet owns the CloudWatch configuration** (not Terraform)
- Manages `amazon-cloudwatch-agent` package (ensures installed)
- Creates config file from ERB template with log group from Terraform custom facts
- Manages service lifecycle (running, enabled)
- Conditional execution based on `$facts['openvpn']['cloudwatch_log_group']`
- Uses `refreshonly` for idempotent configuration

**Logs Collected** (7 log streams):
1. `/var/log/openvpn/openvpn.log` - Main OpenVPN logs
2. `/var/log/openvpn/openvpn-status.log` - Connection status
3. `/var/log/auth.log` - Authentication attempts
4. `/var/log/syslog` - General system messages
5. `/var/log/kern.log` - Kernel messages (runtime)
6. `/var/log/dmesg` - Boot-time kernel messages
7. `/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log` - CloudWatch agent logs

---

## Context

The `terraform-aws-openvpn` module creates CloudWatch log groups in AWS.
**Puppet manages the CloudWatch agent** (package, configuration, and service) on OpenVPN servers.

### Division of Responsibilities

**Terraform manages** (infrastructure):
1. **CloudWatch log groups** in AWS
2. **Provides custom facts** to Puppet with the log group name
3. **Optional**: Can install package via cloud-init for faster bootstrap

**Puppet manages** (configuration):
1. ✅ **Package**: Ensures `amazon-cloudwatch-agent` is installed
2. ✅ **Configuration**: Creates `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` from template
3. ✅ **Service**: Starts and enables the CloudWatch agent service
4. ✅ **Lifecycle**: Restarts service when config changes

### What Terraform Provides

**Terraform custom facts** (passed to Puppet):
```yaml
custom_facts:
  openvpn:
    cloudwatch_log_group: "/aws/openvpn/development/openvpn"
```

Puppet uses `$facts['openvpn']['cloudwatch_log_group']` to:
- Determine if CloudWatch logging is enabled
- Populate the log group name in the configuration template

### What Puppet Does

Puppet manages the complete CloudWatch agent lifecycle:

1. ✅ **Package management**: Ensures `amazon-cloudwatch-agent` is installed
2. ✅ **Configuration management**: Creates config file from ERB template
3. ✅ **Service management**: Starts, enables, and monitors the service
4. ✅ **Idempotency**: Only reconfigures when config changes (using `refreshonly`)

## Implementation Requirements

### File Location

Modify the OpenVPN server Puppet manifest:
- **Repository**: `puppet-code` (https://github.com/infrahouse/puppet-code)
- **File**: `modules/profile/manifests/openvpn_server.pp` (or wherever the openvpn_server role is defined)

### Puppet Code to Add

The Puppet manifest should include logic similar to this:

```puppet
# CloudWatch Logs Agent management for OpenVPN server
# The agent package and configuration are deployed by Terraform via cloud-init
# Puppet manages the service lifecycle

# Ensure the package is installed (redundant check, cloud-init should have done this)
package { 'amazon-cloudwatch-agent':
  ensure => installed,
}

# Only manage the service if the cloudwatch_log_group fact is present
# This fact is provided by Terraform in custom_facts
if $facts['openvpn'] and $facts['openvpn']['cloudwatch_log_group'] {

  # Start and enable the CloudWatch Logs Agent service
  # The configuration file is already deployed by Terraform at:
  # /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

  exec { 'start-cloudwatch-agent':
    command => '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',
    unless  => '/bin/systemctl is-active amazon-cloudwatch-agent',
    require => Package['amazon-cloudwatch-agent'],
  }

  # Ensure the service stays running
  service { 'amazon-cloudwatch-agent':
    ensure  => running,
    enable  => true,
    require => Exec['start-cloudwatch-agent'],
  }

  # Optionally: log the CloudWatch log group name for debugging
  notify { "CloudWatch Logs enabled for log group: ${facts['openvpn']['cloudwatch_log_group']}":
    require => Service['amazon-cloudwatch-agent'],
  }
}
```

### Alternative: Using systemd Service Directly

If you prefer to use systemd service management directly (cleaner approach):

```puppet
# CloudWatch Logs Agent management for OpenVPN server

if $facts['openvpn'] and $facts['openvpn']['cloudwatch_log_group'] {

  # Ensure package is installed
  package { 'amazon-cloudwatch-agent':
    ensure => installed,
  }

  # Ensure the CloudWatch agent is configured and started
  # Configuration file already exists from cloud-init
  exec { 'configure-cloudwatch-agent':
    command => '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',
    creates => '/opt/aws/amazon-cloudwatch-agent/etc/config.json',
    require => Package['amazon-cloudwatch-agent'],
    notify  => Service['amazon-cloudwatch-agent'],
  }

  # Manage the systemd service
  service { 'amazon-cloudwatch-agent':
    ensure  => running,
    enable  => true,
    require => Exec['configure-cloudwatch-agent'],
  }
}
```

### Key Points

1. **Conditional execution**: Only manage CloudWatch agent if `$facts['openvpn']['cloudwatch_log_group']` exists
   - This fact is provided by Terraform
   - If the fact is missing, Terraform didn't configure logging, so Puppet should skip it

2. **Package management**: Ensure `amazon-cloudwatch-agent` package is installed
   - Cloud-init should have already installed it
   - Puppet ensures it stays installed

3. **Service configuration**: Use `amazon-cloudwatch-agent-ctl` to load configuration
   - Configuration file path: `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
   - This file is deployed by Terraform via cloud-init `extra_files`
   - Command: `-a fetch-config -m ec2 -s -c file:/path/to/config.json`

4. **Service management**: Ensure the service is running and enabled
   - Service name: `amazon-cloudwatch-agent`
   - Should start on boot
   - Should restart if it crashes

## Testing

After implementing the Puppet changes, verify:

1. **Service is running**:
   ```bash
   sudo systemctl status amazon-cloudwatch-agent
   ```

2. **Configuration is loaded**:
   ```bash
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a query -m ec2 -c default
   ```

3. **Logs are being shipped**:
   ```bash
   # Check CloudWatch agent logs
   sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
   ```

4. **Logs appear in CloudWatch**:
   - Use AWS Console or CLI to verify logs appear in CloudWatch Logs
   - Log group: `/aws/openvpn/{environment}/{service_name}`
   - Log streams: `{instance_id}/openvpn.log`, `{instance_id}/openvpn-status.log`, `{instance_id}/auth.log`

## Integration with terraform-aws-openvpn

The Terraform module provides these inputs to Puppet via custom facts:

```hcl
custom_facts = {
  openvpn = {
    cloudwatch_log_group = aws_cloudwatch_log_group.openvpn.name
    # Example: "/aws/openvpn/development/openvpn"
  }
}
```

Puppet can access this via: `$facts['openvpn']['cloudwatch_log_group']`

## References

- **CloudWatch Agent Documentation**: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-EC2-Instance.html
- **Agent Control Script**: `/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl`
- **Terraform Module**: `terraform-aws-openvpn` (already implemented)
- **Test File**: `terraform-aws-openvpn/tests/test_module.py::test_cloudwatch_logging()`

## Success Criteria

✅ CloudWatch agent service starts automatically after Puppet run
✅ Service is enabled to start on boot
✅ Logs from `/var/log/openvpn/*.log` and `/var/log/auth.log` appear in CloudWatch
✅ `terraform-aws-openvpn` pytest tests pass (specifically `test_cloudwatch_logging()`)
✅ Puppet runs are idempotent (no changes on subsequent runs if service is already running)

## Questions?

If you need clarification on any part of this implementation, please ask!
