# @summary: Installs and configures webserver.
class profile::webserver () {
  include 'profile::base'

  package { 'nginx-core':
    ensure => present
  }

  service { 'nginx':
    ensure => 'running'
  }
}
