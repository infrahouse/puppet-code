# @summary: Installs TLS certificates.
class profile::elastic::tls (
) {

  $hostname = $facts['networking']['hostname']
  $le_domain = $facts['letsencrypt']['domain']
  $le_fqdn = "${hostname}.${le_domain}"

  $tsl_dir = '/etc/elasticsearch/tls'
  file { $tsl_dir:
    ensure => directory,
    owner  => 'elasticsearch',
    mode   => '0700',
  }

  # CA key
  $ca_key = "${tsl_dir}/ca.key"
  file { $ca_key:
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    content => aws_get_secret(
      $facts['elasticsearch']['ca_key_secret'], $facts['ec2_metadata']['placement']['region']
    )
  }
  # CA certificate
  $ca_cert = "${tsl_dir}/ca.cert"
  file { $ca_cert:
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    content => aws_get_secret(
      $facts['elasticsearch']['ca_cert_secret'], $facts['ec2_metadata']['placement']['region']
    )
  }

  # Node private key
  $node_key = "${tsl_dir}/${le_fqdn}.pem"
  exec { 'generate_node_key':
    command => "openssl genrsa -out ${node_key} 4096",
    creates => $node_key,
    path    => ['/usr/bin', '/usr/local/bin'],
    require => Package['openssl'],
  }
  file { $node_key:
    ensure  => present,
      owner => 'elasticsearch',
      mode  => '0600',
    require => Exec[generate_node_key],
  }

  # Certificate request
  $node_cert_request = "${tsl_dir}/${le_fqdn}.csr"
  exec { 'generate_node_csr':
    command => "openssl req -new -key ${node_key} -out ${node_cert_request} -subj '/C=US/ST=CA/L=San Francisco/O=InfraHouse/CN=${le_fqdn}'",
    creates => $node_cert_request,
    path    => ['/usr/bin', '/usr/local/bin'],
    require => [
      File[$node_key],
    ]
  }
  file { $node_cert_request:
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    require => Exec[generate_node_csr],
  }

  # Sign node certificate
  $node_cert = "${tsl_dir}/${le_fqdn}.cert"
  exec { 'generate_node_pem':
    command => @("EOF"),
    openssl x509 \
      -req -in ${node_cert_request} \
      -CA ${ca_cert} \
      -CAkey ${ca_key} \
      -CAcreateserial \
      -out ${node_cert} \
      -days 3650 \
      -sha256
    | EOF
    creates => $node_cert,
    path    => ['/usr/bin', '/usr/local/bin'],
    require => [
      File[$node_cert_request],
      File[$ca_cert],
      File[$ca_key],
    ]
  }
  file { $node_cert:
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    require => Exec[generate_node_pem],
  }
# Let's encrypt root certificates
  package {'ca-certificates':
    ensure => present,
  }
  file { '/etc/elasticsearch/tls/ISRG_Root_X1.crt':
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    source  => '/usr/share/ca-certificates/mozilla/ISRG_Root_X1.crt',
    links   => follow,
    require => [
      Package['ca-certificates']
    ]
  }

  file { '/etc/elasticsearch/tls/ISRG_Root_X2.crt':
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    source  => '/usr/share/ca-certificates/mozilla/ISRG_Root_X2.crt',
    links   => follow,
    require => [
      Package['ca-certificates']
    ]
  }
}
