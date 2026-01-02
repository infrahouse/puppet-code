# Shared CloudWatch agent base class
#
# Provides common resources and configuration for CloudWatch agent:
# - CloudWatch agent package, user, and service
# - Systemd drop-in for supplementary groups (adm group for log access)
# - Monitoring script
# - Common logs and metrics configuration
#
# Service-specific classes should include this class and pass their
# extra_logs and extra_procstat parameters for service-specific collection.
#
# @param cloudwatch_log_group CloudWatch log group name (required)
# @param cloudwatch_namespace CloudWatch metrics namespace (required)
# @param extra_logs Array of service-specific log configs [{path, stream}]
# @param extra_procstat Array of additional process patterns to monitor
# @param audit_log_file Path to the audit log file
# @param audit_log_dir Path to the audit log directory
# @param config_file Path to the CloudWatch agent config file
#
class profile::cloudwatch_agent (
  String $cloudwatch_log_group,
  String $cloudwatch_namespace,
  Array  $extra_logs            = [],
  Array  $extra_procstat        = [],
  String $audit_log_file        = '/var/log/audit/audit.log',
  String $audit_log_dir         = '/var/log/audit',
  String $config_file           = '/etc/aws/amazon-cloudwatch-agent.json',
) {

  # Common logs collected by all services
  $common_logs = [
    { 'path' => '/var/log/audit/audit.log', 'stream' => 'audit/security' },
    { 'path' => '/var/log/auth.log', 'stream' => 'auth/ssh' },
    { 'path' => '/var/log/syslog', 'stream' => 'system/syslog' },
    { 'path' => '/var/log/kern.log', 'stream' => 'system/kernel' },
    { 'path' => '/var/log/dpkg.log', 'stream' => 'system/packages' },
    { 'path' => '/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log', 'stream' => 'cloudwatch/agent' },
  ]

  # Common process patterns monitored by all services
  $common_procstat = ['auditd']

  # Merge common + service-specific
  $all_logs = $common_logs + $extra_logs
  $all_procstat = $common_procstat + $extra_procstat

  # Ensure the CloudWatch agent package is installed
  package { 'amazon-cloudwatch-agent':
    ensure => installed,
  }

  # Add cwagent user to groups needed to read log files
  # adm: for /var/log/syslog, /var/log/auth.log, /var/log/kern.log
  user { 'cwagent':
    ensure     => present,
    groups     => ['adm'],
    membership => minimum,
    require    => Package['amazon-cloudwatch-agent'],
  }

  # Ensure config directory exists
  file { '/etc/aws':
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Package['amazon-cloudwatch-agent'],
  }

  # Systemd drop-in to ensure CloudWatch agent gets supplementary groups
  # The default unit file doesn't call initgroups(), so we must specify groups explicitly
  file { '/etc/systemd/system/amazon-cloudwatch-agent.service.d':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/systemd/system/amazon-cloudwatch-agent.service.d/groups.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "[Service]\nSupplementaryGroups=adm\n",
    require => File['/etc/systemd/system/amazon-cloudwatch-agent.service.d'],
    notify  => Exec['systemctl-daemon-reload-cloudwatch'],
  }

  exec { 'systemctl-daemon-reload-cloudwatch':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
  }

  # Monitoring script for checking CloudWatch agent status
  file { '/usr/local/bin/check-cloudwatch-agent':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    content => '#!/bin/bash
# Check CloudWatch agent status
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2
',
  }

  # Deploy CloudWatch agent configuration
  file { $config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => template('profile/cloudwatch_agent/amazon-cloudwatch-agent.json.erb'),
    require => [
      File['/etc/aws'],
      Package['amazon-cloudwatch-agent'],
    ],
    notify  => Exec['configure-cloudwatch-agent'],
  }

  # Configure the CloudWatch agent (triggered by config file changes)
  exec { 'configure-cloudwatch-agent':
    command     => "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
-a fetch-config -m ec2 -c file:${config_file}",
    refreshonly => true,
    require     => [
      File['/etc/aws'],
      User['cwagent'],
    ],
    notify      => Service['amazon-cloudwatch-agent'],
  }

  # Manage the CloudWatch agent service
  # Subscribe to daemon-reload to restart after systemd config changes
  service { 'amazon-cloudwatch-agent':
    ensure    => running,
    enable    => true,
    require   => [
      Package['amazon-cloudwatch-agent'],
      User['cwagent'],
      Exec['configure-cloudwatch-agent'],
    ],
    subscribe => Exec['systemctl-daemon-reload-cloudwatch'],
  }

}
