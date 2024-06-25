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
}
