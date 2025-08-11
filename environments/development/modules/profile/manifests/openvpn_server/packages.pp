# @summary: Installs OpenVPN packages.
class profile::openvpn_server::packages (
  String $openvp_config_directory,
) {

  package { [
    'openvpn',
    'openssl',
  ]:
    ensure  => present,
    require => Mount[$openvp_config_directory]
  }

  package { 'easy-rsa':
    ensure => '3.1.7-2'
  }

}
