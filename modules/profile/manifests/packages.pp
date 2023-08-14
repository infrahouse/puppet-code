# @summary: Installs foundation packages to be expected on all hosts.
class profile::packages () {

  package { [
    'awscli',
    'net-tools'
  ]:
    ensure => present
  }

}
