# @summary: Installs OpenVPN packages.
class profile::openvpn_server::packages () {

  package { 'openvpn':
    ensure  => present,
  }

}
