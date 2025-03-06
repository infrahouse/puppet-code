# @summary: Configures jumphost resources
class profile::jumphost () {
  include 'profile::echo'

  $ssh_service = ($facts['os']['name'] == 'Ubuntu' and $facts['os']['release']['major'] == '24.04') ? {
    true  => 'ssh',
    false => 'sshd',
  }

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
    notify => Service[$ssh_service],
  }

  service { $ssh_service:
    ensure  => running,
    require => Package['openssh-server'],
  }

}
