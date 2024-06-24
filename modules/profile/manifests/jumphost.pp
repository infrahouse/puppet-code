# @summary: Configures jumphost resources
class profile::jumphost () {

  $packages = {
    'pdsh' => present,
  }

  $packages.map |$item| {
    package { $item[0]:
      ensure => $item[1]
    }
  }
}
