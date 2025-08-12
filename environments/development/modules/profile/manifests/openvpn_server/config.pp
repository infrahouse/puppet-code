# @summary: Installs OpenVPN server config.
class profile::openvpn_server::config (
  Integer $openvpn_port,
  String $openvp_config_directory,
  String $openvpn_easyrsa_req_country,
  String $openvpn_easyrsa_req_province,
  String $openvpn_easyrsa_req_city,
  String $openvpn_easyrsa_req_org,
  String $openvpn_easyrsa_req_email,
  String $openvpn_easyrsa_req_ou,
  String $openvpn_topology,
  String $openvpn_network,
  String $openvpn_netmask,
) {

  $dns_name = $facts['efs']['dns_name']
  $nfs_device = "${dns_name}:/"
  $openvpn_easyrsa_passin_file = "${openvp_config_directory}/ca_passphrase"
  $openvpn_easyrsa_tmp_dir = '/tmp'

  $openvpn_routes = 'routes' in $facts['openvpn'] ? {
    true => $facts['openvpn']['routes'],
    false => [],
  }

  class { 'profile::openvpn_server::volume':
    nfs_device   => $nfs_device,
    mount_target => $openvp_config_directory,
  }

  file { $openvpn_easyrsa_passin_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0400',
    content => aws_get_secret(
      $facts['openvpn']['ca_key_passphrase_secret'],
      $facts['ec2_metadata']['placement']['region']
    ),
    require => [
      Mount[$openvp_config_directory],
    ]
  }

  file { "${openvp_config_directory}/server.conf":
    ensure  => file,
    content => template('profile/openvpn_server/server.conf.erb'),
    notify  => Service['openvpn@server'],
    require => [
      Mount[$openvp_config_directory],
    ],
  }

  exec {'generate_dh2048_pem':
    path    => '/usr/bin',
    command => 'openssl dhparam -out dh2048.pem 2048',
    cwd     => $openvp_config_directory,
    creates => "${openvp_config_directory}/dh2048.pem",
    require => [
      Mount[$openvp_config_directory],
      Package['openssl'],
    ],
  }
  file { "${openvp_config_directory}/dh2048.pem":
    owner   => root,
    group   => root,
    mode    => '0644',
    require => Exec[generate_dh2048_pem]
  }

  exec {'generate_ta_key':
    path    => '/usr/bin:/usr/sbin',
    command => 'openvpn --genkey tls-auth ta.key',
    cwd     => $openvp_config_directory,
    creates => "${openvp_config_directory}/ta.key",
    require => [
      Mount[$openvp_config_directory],
      Package['openssl'],
    ],
  }
  file { "${openvp_config_directory}/ta.key":
    owner   => root,
    group   => root,
    mode    => '0600',
    require => Exec[generate_ta_key]
  }

  file { $openvpn_easyrsa_tmp_dir:
    ensure => directory,
  }

  file { "${openvp_config_directory}/vars":
    ensure  => file,
    content => template('profile/openvpn_server/vars.erb'),
    require => [
      Mount[$openvp_config_directory]
    ],
  }

  exec { 'generate_pki':
    command => '/usr/share/easy-rsa/easyrsa init-pki',
    cwd     => $openvp_config_directory,
    creates => "${openvp_config_directory}/pki",
    require => [
      Mount[$openvp_config_directory],
      Package[easy-rsa]
    ]
  }

  exec { 'generate_ca':
    command     => "/usr/share/easy-rsa/easyrsa --vars=${openvp_config_directory}/vars build-ca",
    cwd         => $openvp_config_directory,
    environment => [
      "EASYRSA_PASSIN=file:${openvpn_easyrsa_passin_file}",
    ],
    creates     => "${openvp_config_directory}/pki/private/ca.key",
    require     => [
      Mount[$openvp_config_directory],
      Package[easy-rsa],
      File["${openvp_config_directory}/vars"],
      File[$openvpn_easyrsa_passin_file],
    ]
  }

  exec { 'generate_server_key':
    command     => "/usr/share/easy-rsa/easyrsa --vars=${openvp_config_directory}/vars build-server-full server nopass inline",
    cwd         => $openvp_config_directory,
    environment => [
      "EASYRSA_PASSIN=file:${openvpn_easyrsa_passin_file}",
      "EASYRSA_PASSOUT=file:${openvpn_easyrsa_passin_file}",
    ],
    creates     => "${openvp_config_directory}/pki/private/server.key",
    require     => [
      Mount[$openvp_config_directory],
      Package[easy-rsa],
      File["${openvp_config_directory}/vars"],
      File[$openvpn_easyrsa_passin_file],
    ]
  }

  exec { 'generate_gen_crl':
    command     => "/usr/share/easy-rsa/easyrsa --vars=${openvp_config_directory}/vars gen-crl",
    cwd         => $openvp_config_directory,
    environment => [
      "EASYRSA_PASSIN=file:${openvpn_easyrsa_passin_file}",
      "EASYRSA_PASSOUT=file:${openvpn_easyrsa_passin_file}",
    ],
    creates     => "${openvp_config_directory}/pki/crl.pem",
    require     => [
      Mount[$openvp_config_directory],
      Package[easy-rsa],
      File["${openvp_config_directory}/vars"],
      File[$openvpn_easyrsa_passin_file],
    ]
  }

}
