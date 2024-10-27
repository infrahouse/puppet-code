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

  file { '/etc/nginx/sites-enabled/default':
    ensure  => file,
    source  => 'puppet:///modules/profile/infrahouse.com.conf',
    notify  => Service['nginx'],
    require => Package['nginx-core'],
  }

  package { 'infrahouse-com':
    ensure  => latest,
    require => [
      Package['nginx-core'],
    ]
  }
}
