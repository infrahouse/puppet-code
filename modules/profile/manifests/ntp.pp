# @summary: Installs and configures NTP
class profile::ntp () {

  package { 'chrony':
    ensure => present,
  }

  service { 'chrony':
    ensure  => running,
    require => Package['chrony'],
  }

}
