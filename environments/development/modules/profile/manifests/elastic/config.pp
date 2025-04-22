# @summary: Installs elasicsearch service.
class profile::elastic::config (
  String $role = 'master',
) {

  $elastic_cluster_role = $role
  $elastic_monitoring_role_name = 'anonymous_monitor'

  $hostname = $facts['networking']['hostname']
  $le_domain = $facts['letsencrypt']['domain']
  $le_fqdn = "${hostname}.${le_domain}"

  file { '/etc/elasticsearch/elasticsearch.yml':
    ensure  => file,
    content => template('profile/elasticsearch.yml.erb'),
    notify  => Service['elasticsearch'],
  }

  file { '/etc/elasticsearch/roles.yml':
    ensure  => file,
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
