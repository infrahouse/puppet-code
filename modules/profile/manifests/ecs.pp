# @summary: Installs docker repo, package and starts the service.
class profile::ecs () {
  include 'profile::docker'

  package { 'amazon-ecs-init':
    ensure => latest
  }

  service { 'ecs':
    ensure  => running,
    require => [
      Package['amazon-ecs-init'],
      Service['docker'],
    ]
  }
}
