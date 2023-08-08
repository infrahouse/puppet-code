class profile::packages () {

  package { [
    'awscli',
  ]:
    ensure => present
  }

}
