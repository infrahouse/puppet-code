# CloudWatch agent configuration for Jumphost
class profile::jumphost::cloudwatch_agent {

  # Only configure if CloudWatch log group is provided via Terraform facts
  if $facts['jumphost'] and $facts['jumphost']['cloudwatch_log_group'] {

    $cloudwatch_log_group = $facts['jumphost']['cloudwatch_log_group']
    $config_dir = '/etc/aws'
    $config_file = "${config_dir}/amazon-cloudwatch-agent.json"

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

    # Allow CloudWatch agent to read audit logs
    # Set ACL on audit log directory so cwagent user can read logs
    exec { 'set-audit-log-acl':
      command => '/usr/bin/setfacl -R -m u:cwagent:r-x /var/log/audit && /usr/bin/setfacl -d -m u:cwagent:r-x /var/log/audit',
      unless  => '/usr/bin/getfacl /var/log/audit 2>/dev/null | /usr/bin/grep -q "user:cwagent:r-x"',
      require => [
        Package['acl'],
        User['cwagent'],
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
      notify  => Exec['configure-cloudwatch-agent-jumphost'],
    }

    # Configure and start CloudWatch agent
    exec { 'configure-cloudwatch-agent-jumphost':
      command     => "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
-a fetch-config -m ec2 -s -c file:${config_file}",
      refreshonly => true,
      require     => File[$config_file],
    }

    # Ensure CloudWatch agent service is running
    service { 'amazon-cloudwatch-agent':
      ensure  => running,
      enable  => true,
      require => [
        Package['amazon-cloudwatch-agent'],
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