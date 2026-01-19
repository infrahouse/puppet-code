# @summary: Manages Percona Server MySQL service.
class profile::percona::service () {

  service { 'mysql':
    ensure  => running,
    enable  => true,
    require => Package['percona-server-server'],
  }

}