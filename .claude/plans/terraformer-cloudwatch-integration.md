# Terraformer CloudWatch Agent Integration Plan

## Overview

This plan adds CloudWatch agent integration to the Terraformer role, enabling centralized logging 
and metrics collection. The Terraform module (`terraform-aws-terraformer`) now passes 
CloudWatch configuration via Puppet facts.

## Background

The `terraform-aws-terraformer` module has been updated to:
- Create a CloudWatch log group (`/aws/ec2/terraformer`)
- Pass facts to Puppet:
  - `$facts['terraformer']['cloudwatch_log_group']` - Log group name
  - `$facts['terraformer']['cloudwatch_namespace']` - Metrics namespace (default: `Terraformer/System`)

## Scope

**Environment:** `development` only (initial rollout)

**Files to create:**
- `environments/development/modules/profile/manifests/terraformer/cloudwatch_agent.pp`

**Files to modify:**
- `environments/development/modules/profile/manifests/terraformer.pp`

## Implementation Plan

### Step 1: Create CloudWatch Agent Subclass

Create `environments/development/modules/profile/manifests/terraformer/cloudwatch_agent.pp`:

```puppet
# CloudWatch agent configuration for Terraformer
#
# This class configures the CloudWatch agent for Terraformer by including
# the shared base class with Terraformer-specific log collection.
#
# Terraformer-specific logs:
# - /var/log/terraform/*.log - Terraform operation logs (if present)
#
class profile::terraformer::cloudwatch_agent {

  # Only configure if CloudWatch log group is provided via Terraform facts
  if $facts['terraformer'] and $facts['terraformer']['cloudwatch_log_group'] {

    # Include shared CloudWatch agent base class with Terraformer-specific extras
    class { 'profile::cloudwatch_agent':
      cloudwatch_log_group => $facts['terraformer']['cloudwatch_log_group'],
      cloudwatch_namespace => pick($facts['terraformer']['cloudwatch_namespace'], 'Terraformer/System'),
      extra_logs           => [
        # Terraform logs directory (optional - may not exist on all instances)
        # { 'path' => '/var/log/terraform/*.log', 'stream' => 'terraform/operations' },
      ],
      extra_procstat       => [],
    }

  }
}
```

### Step 2: Create Directory Structure

```bash
mkdir -p environments/development/modules/profile/manifests/terraformer
```

### Step 3: Update Terraformer Profile

Modify `environments/development/modules/profile/manifests/terraformer.pp` to include CloudWatch agent:

```puppet
# @summary: Terraformer profile.
class profile::terraformer (
  $terraform_version = lookup(
    'profile::terraformer::terraform_version', undef, undef, 'latest'
  )
) {
  package { 'terraform':
    ensure => $terraform_version
  }

  # CloudWatch agent for logging and metrics
  include profile::terraformer::cloudwatch_agent
}
```

## Testing Plan

1. **Deploy Puppet changes** to development environment
2. **Test with existing Terraformer instance** (if any):
   ```bash
   # On the terraformer instance
   sudo facter -p terraformer
   sudo puppet agent -t --environment development
   ```
3. **Verify CloudWatch agent**:
   ```bash
   sudo systemctl status amazon-cloudwatch-agent
   sudo /usr/local/bin/check-cloudwatch-agent
   ```
4. **Check CloudWatch Logs** in AWS Console for log streams

## Rollout Sequence

1. Merge this Puppet change to development environment
2. Deploy to development (ih-puppet apply or agent run)
3. Test Terraform module with `make test` (uses development environment)
4. If successful, promote Puppet changes to production
5. Release new Terraform module version

## Dependencies

- `profile::cloudwatch_agent` base class (already exists in development)
- CloudWatch agent package available in APT repository
- Terraform module passing correct facts

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Facts not available on existing instances | Conditional check: `if $facts['terraformer']` |
| CloudWatch agent fails to start | Service has explicit dependencies on config |
| Log group doesn't exist | Terraform creates it before instance boots |

## Verification Commands

After deployment, run these on the Terraformer instance:

```bash
# Check facts are present
sudo facter -p terraformer

# Expected output:
# {
#   cloudwatch_log_group => "/aws/ec2/terraformer",
#   cloudwatch_namespace => "Terraformer/System"
# }

# Check CloudWatch agent status
sudo systemctl status amazon-cloudwatch-agent

# Check agent config
sudo cat /etc/aws/amazon-cloudwatch-agent.json | jq .

# Check logs are being collected
aws logs describe-log-streams \
  --log-group-name "/aws/ec2/terraformer" \
  --order-by LastEventTime \
  --descending
```

## Estimated Effort

- Implementation: 15 minutes
- Testing: 30 minutes
- Total: ~45 minutes
