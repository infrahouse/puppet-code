# @summary: Installs foundation packages to be expected on all hosts.
class profile::packages (
  $packages = lookup(
    'profile::packages', undef, undef, {
      'awscli'             => present,
      'gnupg2'             => present,
      'jq'                 => present,
      'make'               => present,
      'net-tools'          => present,
      'python3'            => present,
      'python-is-python3'  => present,
      'python3-virtualenv' => present,
      'ubuntu-keyring'     => present,
    }
  )
) {

  $packages.map |$item| {
    package { $item[0]:
      ensure => $item[1]
    }
  }
}
