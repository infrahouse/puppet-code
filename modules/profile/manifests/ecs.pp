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
}
