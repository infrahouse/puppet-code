# @summary: Installs Percona Server packages.
class profile::percona::packages () {

  $server_ensure = $profile::percona::server_ensure
  $xtrabackup_package = $profile::percona::xtrabackup_package

  # Config must be in place before package install so MySQL starts correctly
  package { 'percona-server-server':
    ensure  => $server_ensure,
    require => [
      Class['profile::percona::repo'],
      Class['profile::percona::config'],
    ],
  }

  package { 'percona-server-client':
    ensure  => $server_ensure,
    require => Class['profile::percona::repo'],
  }

  package { $xtrabackup_package:
    ensure  => 'installed',
    require => Class['profile::percona::repo'],
  }

}
