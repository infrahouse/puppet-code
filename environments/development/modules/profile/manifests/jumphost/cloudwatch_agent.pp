# CloudWatch agent configuration for Jumphost
#
# @param audit_log_file Path to the audit log file (should match profile::auditd::log_file)
#
class profile::jumphost::cloudwatch_agent (
  String $audit_log_file = '/var/log/audit/audit.log',
) {

  # Only configure if CloudWatch log group is provided via Terraform facts
  if $facts['jumphost'] and $facts['jumphost']['cloudwatch_log_group'] {

    $cloudwatch_log_group = $facts['jumphost']['cloudwatch_log_group']
    $cloudwatch_namespace = $facts['jumphost']['cloudwatch_namespace']
    $config_dir = '/etc/aws'
    $config_file = "${config_dir}/amazon-cloudwatch-agent.json"
    $audit_log_dir = dirname($audit_log_file)
    $ec2_hostname = $facts['networking']['hostname']

    # Ensure config directory exists
    file { $config_dir:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    # Install CloudWatch agent
    package { 'amazon-cloudwatch-agent':
      ensure => installed,
    }

    # Add cwagent user to groups needed to read log files
    # adm: for /var/log/syslog, /var/log/auth.log, /var/log/kern.log
    # utmp: for /var/log/btmp, /var/log/wtmp
    user { 'cwagent':
      ensure     => present,
      groups     => ['adm', 'utmp'],
      membership => minimum,
      require    => Package['amazon-cloudwatch-agent'],
      notify     => Service['amazon-cloudwatch-agent'],
    }

    # Ensure acl package is installed for setting file ACLs
    package { 'acl':
      ensure => installed,
    }

    # Deploy ACL setup script
    file { '/usr/local/bin/set-audit-acl':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => template('profile/jumphost/set-audit-acl.sh.erb'),
    }

    # Deploy ACL verification script
    file { '/usr/local/bin/check-audit-acl':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => template('profile/jumphost/check-audit-acl.sh.erb'),
    }

    # Allow CloudWatch agent to read audit logs
    # Set ACL on audit log directory and files so cwagent user can read logs
    # Note: Depends on sudo class (managed separately) for ACL verification
    exec { 'set-audit-log-acl':
      command => '/usr/local/bin/set-audit-acl',
      unless  => '/usr/local/bin/check-audit-acl',
      require => [
        Class['sudo'],
        Package['acl'],
        User['cwagent'],
        File['/usr/local/bin/set-audit-acl'],
        File['/usr/local/bin/check-audit-acl'],
      ],
    }

    # Deploy CloudWatch agent configuration
    file { $config_file:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0640',
      content => template('profile/jumphost/amazon-cloudwatch-agent.json.erb'),
      require => [
        File[$config_dir],
        Package['amazon-cloudwatch-agent'],
      ],
      notify  => [
        Exec['configure-cloudwatch-agent-jumphost'],
        Service['amazon-cloudwatch-agent'],
      ],
    }

    # Configure and start CloudWatch agent
    exec { 'configure-cloudwatch-agent-jumphost':
      command     => "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
-a fetch-config -m ec2 -s -c file:${config_file}",
      refreshonly => true,
      require     => [
        File[$config_file],
        User['cwagent'],
      ],
    }

    # Ensure CloudWatch agent service is running
    service { 'amazon-cloudwatch-agent':
      ensure  => running,
      enable  => true,
      require => [
        Package['amazon-cloudwatch-agent'],
        User['cwagent'],
        Exec['configure-cloudwatch-agent-jumphost'],
      ],
    }

    # Create monitoring script
    file { '/usr/local/bin/check-cloudwatch-agent':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => '#!/bin/bash
# Check CloudWatch agent status for jumphost
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2
',
    }

    # Ensure agent stays running
    cron { 'ensure-cloudwatch-agent-running':
      command => '/usr/bin/systemctl is-active --quiet amazon-cloudwatch-agent || /usr/bin/systemctl start amazon-cloudwatch-agent',
      minute  => '*/5',
      require => Service['amazon-cloudwatch-agent'],
    }
  }
}
