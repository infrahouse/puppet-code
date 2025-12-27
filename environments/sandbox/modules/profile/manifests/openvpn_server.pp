# @summary: OpenVPN server profile.
class profile::openvpn_server (
  $openvp_config_directory = lookup(
    'profile::openvpn_server::config_directory', undef, undef, '/etc/openvpn'
  ),
  $openvpn_easyrsa_req_country = lookup('profile::openvpn_server::openvpn_easyrsa_req_country', undef, undef, 'US' ),
  $openvpn_easyrsa_req_province = lookup('profile::openvpn_server::openvpn_easyrsa_req_province', undef, undef, 'California' ),
  $openvpn_easyrsa_req_city = lookup('profile::openvpn_server::openvpn_easyrsa_req_city', undef, undef, 'San Francisco' ),
  $openvpn_easyrsa_req_org = lookup('profile::openvpn_server::openvpn_easyrsa_req_org', undef, undef, 'InfraHouse Inc.' ),
  $openvpn_easyrsa_req_email = lookup('profile::openvpn_server::openvpn_easyrsa_req_email', undef, undef, 'security@infrahouse.com' ),
  $openvpn_easyrsa_req_ou = lookup('profile::openvpn_server::openvpn_easyrsa_req_ou', undef, undef, 'Security Organization' ),
  $openvpn_topology = lookup('profile::openvpn_server::openvpn_topology', undef, undef, 'net30' ),
  $openvpn_network = lookup('profile::openvpn_server::openvpn_network', undef, undef, '172.16.0.0' ),
  $openvpn_netmask = lookup('profile::openvpn_server::openvpn_netmask', undef, undef, '255.255.0.0' ),
) {

  class { 'profile::openvpn_server::packages':
    openvp_config_directory => $openvp_config_directory,
  }

  class { 'profile::openvpn_server::config':
    openvp_config_directory      => $openvp_config_directory,
    openvpn_port                 => $facts['openvpn']['openvpn_port'],
    openvpn_topology             => $openvpn_topology,
    openvpn_network              => $openvpn_network,
    openvpn_netmask              => $openvpn_netmask,
    openvpn_easyrsa_req_country  => $openvpn_easyrsa_req_country,
    openvpn_easyrsa_req_province => $openvpn_easyrsa_req_province,
    openvpn_easyrsa_req_city     => $openvpn_easyrsa_req_city,
    openvpn_easyrsa_req_org      => $openvpn_easyrsa_req_org,
    openvpn_easyrsa_req_email    => $openvpn_easyrsa_req_email,
    openvpn_easyrsa_req_ou       => $openvpn_easyrsa_req_ou,
  }

  class { 'profile::openvpn_server::service':
    openvp_config_directory => $openvp_config_directory,
  }

  include 'profile::openvpn_server::nat'
  include 'profile::openvpn_server::auditd'
  include 'profile::openvpn_server::cloudwatch_agent'

}
