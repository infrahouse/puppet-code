# @summary: OpenVPN server profile.
class profile::openvpn_server (
  $openvpn_port = lookup(
    'profile::openvpn_server::port', undef, undef, 1194
  ),
  $openvp_config_directory = lookup(
    'profile::openvpn_server::config_directory', undef, undef, '/etc/openvpn'
  ),
  $openvpn_easyrsa_req_country = lookup('profile::openvpn_server::openvpn_easyrsa_req_country', undef, undef, 'US' ),
  $openvpn_easyrsa_req_province = lookup('profile::openvpn_server::openvpn_easyrsa_req_province', undef, undef, 'California' ),
  $openvpn_easyrsa_req_city = lookup('profile::openvpn_server::openvpn_easyrsa_req_city', undef, undef, 'San Francisco' ),
  $openvpn_easyrsa_req_org = lookup('profile::openvpn_server::openvpn_easyrsa_req_org', undef, undef, 'InfraHouse Inc.' ),
  $openvpn_easyrsa_req_email = lookup('profile::openvpn_server::openvpn_easyrsa_req_email', undef, undef, 'security@infrahouse.com' ),
  $openvpn_easyrsa_req_ou = lookup('profile::openvpn_server::openvpn_easyrsa_req_ou', undef, undef, 'Security Organization' ),
  $openvpn_easyrsa_req_cn = lookup('profile::openvpn_server::openvpn_easyrsa_req_cn', undef, undef, 'InfraHouse OpenVPN Root CA' ),
) {

  class { 'profile::openvpn_server::packages':
    openvp_config_directory => $openvp_config_directory,
  }

  class { 'profile::openvpn_server::config':
    openvpn_port                 => $openvpn_port,
    openvp_config_directory      => $openvp_config_directory,

    openvpn_easyrsa_req_country  => $openvpn_easyrsa_req_country,
    openvpn_easyrsa_req_province => $openvpn_easyrsa_req_province,
    openvpn_easyrsa_req_city     => $openvpn_easyrsa_req_city,
    openvpn_easyrsa_req_org      => $openvpn_easyrsa_req_org,
    openvpn_easyrsa_req_email    => $openvpn_easyrsa_req_email,
    openvpn_easyrsa_req_ou       => $openvpn_easyrsa_req_ou,
    openvpn_easyrsa_req_cn       => $openvpn_easyrsa_req_cn,
  }

  class { 'profile::openvpn_server::service':
    openvp_config_directory => $openvp_config_directory,
  }

}
