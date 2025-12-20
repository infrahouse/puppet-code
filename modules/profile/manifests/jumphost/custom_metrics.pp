# Custom CloudWatch metrics for Jumphost
#
# Publishes security and operational metrics to CloudWatch:
# - ServiceStatus: auditd process health
# - DiskSpaceUsed: root filesystem usage
# - AuditEventsLost: audit event loss detection
# - FailedLogins: SSH authentication failures
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
  # (ServiceStatus, AuditEventsLost, FailedLogins need 60s interval)
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
