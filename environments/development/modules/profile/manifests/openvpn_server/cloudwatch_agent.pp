# @summary: Manages CloudWatch Logs Agent for OpenVPN server.
#
# This class manages the CloudWatch agent package, configuration, and service.
# Puppet is the source of truth for the CloudWatch agent configuration.
#
class profile::openvpn_server::cloudwatch_agent {

  # Only manage CloudWatch agent if the cloudwatch_log_group fact is present
  # This fact is provided by Terraform in custom_facts
  if $facts['openvpn'] and $facts['openvpn']['cloudwatch_log_group'] {

    $cloudwatch_log_group = $facts['openvpn']['cloudwatch_log_group']
    $config_dir = '/opt/aws/amazon-cloudwatch-agent/etc'
    $config_file = "${config_dir}/amazon-cloudwatch-agent.json"

    # Ensure the CloudWatch agent package is installed
    package { 'amazon-cloudwatch-agent':
      ensure => installed,
    }

    # Ensure the config directory exists
    file { $config_dir:
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      require => Package['amazon-cloudwatch-agent'],
    }

    # Deploy the CloudWatch agent configuration file
    file { $config_file:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('profile/openvpn_server/amazon-cloudwatch-agent.json.erb'),
      require => File[$config_dir],
      notify  => Exec['configure-cloudwatch-agent'],
    }

    # Configure and start the CloudWatch agent
    exec { 'configure-cloudwatch-agent':
      command     => '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
-a fetch-config -m ec2 -s \
-c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',
      refreshonly => true,
      require     => [Package['amazon-cloudwatch-agent'], File[$config_file]],
      notify      => Service['amazon-cloudwatch-agent'],
    }

    # Manage the CloudWatch agent service
    service { 'amazon-cloudwatch-agent':
      ensure  => running,
      enable  => true,
      require => Exec['configure-cloudwatch-agent'],
    }

  }

}