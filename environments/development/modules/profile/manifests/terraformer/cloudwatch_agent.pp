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