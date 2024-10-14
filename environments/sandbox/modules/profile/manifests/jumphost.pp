# @summary: Configures jumphost resources
class profile::jumphost () {
  include 'profile::echo'

  $packages = {
    'pdsh' => present,
  }

  $packages.map |$item| {
    package { $item[0]:
      ensure => $item[1]
    }
  }

  package { 'openssh-client':
    ensure => latest,
  }

  package { 'openssh-server':
    ensure => latest,
    notify => Service[sshd],
  }

  service { 'sshd':
    ensure  => running,
    require => Package[openssh-server],
  }

}
