# @summary: Installs docker repo, package and starts the service.
class profile::ecs () {
  include 'profile::docker'

  package { 'amazon-ecs-init':
    ensure => latest
  }

  package { 'cgroup-tools':
    ensure => latest
  }

  service { 'ecs':
    ensure  => running,
    require => [
      Package['amazon-ecs-init'],
      Package['cgroup-tools'],
      Service['docker'],
    ]
  }

  $ecs_cluster = $facts['ecs']['cluster']
  $ecs_loglevel = $facts['ecs']['loglevel']

  file { '/etc/ecs/ecs.config':
    ensure  => file,
    content => template('profile/ecs/ecs.config.erb'),
    notify  => Service['ecs'],
    require => [
      Package['amazon-ecs-init'],
    ],
  }
}
