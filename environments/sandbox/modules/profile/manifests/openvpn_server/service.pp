# @summary: Installs OpenVPN server service.
class profile::openvpn_server::service (
  String $openvp_config_directory,
) {

  service { 'openvpn@server':
    ensure  => running,
    require => [
      Package['openvpn'],
      File["${openvp_config_directory}/server.conf"],
      Exec[generate_ca],
    ]
  }
}
