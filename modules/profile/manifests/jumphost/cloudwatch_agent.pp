# CloudWatch agent configuration for Jumphost
#
# This class configures the CloudWatch agent for Jumphost by including
# the shared base class with Jumphost-specific log collection.
#
# Jumphost-specific logs:
# - /var/log/fail2ban.log - Intrusion prevention
#
class profile::jumphost::cloudwatch_agent {

  # Only configure if CloudWatch log group is provided via Terraform facts
  if $facts['jumphost'] and $facts['jumphost']['cloudwatch_log_group'] {

    # Include shared CloudWatch agent base class with Jumphost-specific extras
    class { 'profile::cloudwatch_agent':
      cloudwatch_log_group => $facts['jumphost']['cloudwatch_log_group'],
      cloudwatch_namespace => pick($facts['jumphost']['cloudwatch_namespace'], 'Jumphost/System'),
      extra_logs           => [
        { 'path' => '/var/log/fail2ban.log', 'stream' => 'security/fail2ban' },
      ],
    }

  }
}
