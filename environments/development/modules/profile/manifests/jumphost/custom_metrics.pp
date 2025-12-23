# Custom CloudWatch metrics for Jumphost
#
# Publishes security and operational metrics to CloudWatch:
# - ServiceStatus: auditd process health (1=running, 0=stopped)
# - AuditEventsLost: delta of lost audit events since last check
# - FailedLogins: SSH authentication failures (from journalctl)
#
class profile::jumphost::custom_metrics {

  # Variables for template
  $ec2_hostname = $facts['networking']['hostname']
  $region = $facts['ec2_metadata']['placement']['region']
  $cloudwatch_namespace = $facts['jumphost']['cloudwatch_namespace']
  # $environment is a built-in Puppet variable, available in template scope

  # Deploy metrics collection script
  file { '/usr/local/bin/publish-jumphost-metrics':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    content => template('profile/jumphost/publish-jumphost-metrics.sh.erb'),
  }

  # Create state directory for tracking deltas
  file { '/var/run/jumphost-metrics':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Schedule metrics collection every minute
  cron { 'publish-jumphost-metrics':
    command => '/usr/local/bin/publish-jumphost-metrics',
    user    => 'root',
    minute  => '*',
    require => [
      File['/usr/local/bin/publish-jumphost-metrics'],
      File['/var/run/jumphost-metrics'],
    ],
  }
}
