# @summary: Installs and configures webserver.
class profile::webserver () {
  include 'profile::base'

  package { 'nginx-core':
    ensure => present,
  }

  service { 'nginx':
    ensure  => 'running',
    require => [
    Package['nginx-core'],
    ]
  }

  package { 'infrahouse-com':
    ensure  => latest,
    require => [
      Package['nginx-core'],
    ]
  }

  file { '/var/www/html/index.html':
    ensure  => present,
    source  => 'puppet:///modules/profile/index.html',
    require => [
      Package['nginx-core'],
    ]
  }
}
