# @summary: Installs Percona Server packages.
class profile::percona::packages () {

  # Config must be in place before package install so MySQL starts correctly
  package { 'percona-server-server':
    ensure  => 'installed',
    require => [
      Class['profile::percona::repo'],
      Class['profile::percona::config'],
    ],
  }

  package { 'percona-server-client':
    ensure  => 'installed',
    require => Class['profile::percona::repo'],
  }

}