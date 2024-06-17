# @summary: Installs elasicsearch service.
class profile::elastic::config (
  String $role = 'master',
  String $monitoring_role_name = lookup(
    'profile::elastic::config::monitoring_role_name',
    undef,
    undef,
    'monitoring_user',
  ),
) {

  $elastic_cluster_role = $role
  $elastic_monitoring_role_name = $monitoring_role_name

  $hostname = $facts['networking']['hostname']
  $le_domain = $facts['letsencrypt']['domain']
  $le_fqdn = "${hostname}.${le_domain}"

  file { '/etc/elasticsearch/letsencrypt':
    ensure => directory,
    owner  => 'elasticsearch',
    mode   => '0700',
  }

  file { '/etc/elasticsearch/letsencrypt/privkey.pem':
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    source  => "/etc/letsencrypt/live/${le_fqdn}/privkey.pem",
    links   => follow,
    require => [
      Exec['obtain_certificate'],
      File['/etc/elasticsearch/letsencrypt'],
    ]
  }

  file { '/etc/elasticsearch/letsencrypt/cert.pem':
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    source  => "/etc/letsencrypt/live/${le_fqdn}/cert.pem",
    links   => follow,
    require => [
      Exec['obtain_certificate'],
      File['/etc/elasticsearch/letsencrypt'],
    ]
  }

  file { '/etc/elasticsearch/letsencrypt/fullchain.pem':
    ensure  => present,
    owner   => 'elasticsearch',
    mode    => '0600',
    source  => "/etc/letsencrypt/live/${le_fqdn}/fullchain.pem",
    links   => follow,
    require => [
      Exec['obtain_certificate'],
      File['/etc/elasticsearch/letsencrypt'],
    ]
  }

  file { '/etc/elasticsearch/elasticsearch.yml':
    ensure  => file,
    content => template('profile/elasticsearch.yml.erb'),
    notify  => Service['elasticsearch'],
    require => [
      Exec['obtain_certificate']
    ],
  }

  if $monitoring_role_name != 'monitoring_user' {
    $ensure_role_file = 'file'
  } else {
    $ensure_role_file = 'absent'
  }

  file { '/etc/elasticsearch/roles.yml':
    ensure  => $ensure_role_file,
    content => template('profile/elasticsearch/roles.yml.erb'),
    owner   => 'elasticsearch',
    mode    => '0644',
    notify  => Service['elasticsearch'],
  }


  $total_ram = $facts['memory']['system']['total_bytes']
  $es_heap_size = $total_ram/2

  file { '/etc/elasticsearch/jvm.options.d/heap.options':
    ensure  => file,
    content => template('profile/elasticsearch/heap.erb'),
    notify  => Service['elasticsearch'],
    require => [
      Package['elasticsearch']
    ],
  }
}
