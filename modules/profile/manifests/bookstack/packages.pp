# @summary: Installs bookstack packages.
class profile::bookstack::packages () {

  package { [
    'nginx-core',
    'php',
    'phph-cli'
  ]:
    ensure => present,
  }
}
