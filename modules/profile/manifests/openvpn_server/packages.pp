# @summary: Installs OpenVPN packages.
class profile::openvpn_server::packages (
  String $openvp_config_directory,
) {

  package { [
    'openvpn',
    'openssl',
    'easy-rsa',
  ]:
    ensure  => present,
    require => Mount[$openvp_config_directory]
  }

}
