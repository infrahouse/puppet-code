# @summary: Configure Name Service Cache Daemon (nscd)
#
# nscd caches name service lookups (users, groups, hosts, services)
# This prevents repeated LDAP/DNS queries and eliminates failed socket
# connection attempts from services like xinetd.
class profile::nscd () {

  package { 'nscd':
    ensure => present,
  }

  service { 'nscd':
    ensure  => running,
    enable  => true,
    require => Package['nscd'],
  }
}