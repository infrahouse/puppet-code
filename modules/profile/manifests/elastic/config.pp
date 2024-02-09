# @summary: Installs elasicsearch service.
class profile::elastic::config (
  String $role = 'master',
) {

  $elastic_cluster_role = $role
  file { '/etc/elasticsearch/elasticsearch.yml':
    ensure  => file,
    content => template('profile/elasticsearch.yml.erb'),
    notify  => Service['elasticsearch'],
  }
}
