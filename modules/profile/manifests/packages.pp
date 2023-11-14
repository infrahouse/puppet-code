# @summary: Installs foundation packages to be expected on all hosts.
class profile::packages () {

  package { [
    'awscli',
    'jq',
    'make',
    'net-tools',
    'python3',
    'python-is-python3',
    'python3-virtualenv'
  ]:
    ensure => present
  }

}
