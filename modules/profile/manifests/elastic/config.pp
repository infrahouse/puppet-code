# @summary: Installs elasicsearch service.
class profile::elastic::config (
  String $role = 'master',
  String $cluster_name = 'elasticsearch',
) {

  $elastic_cluster_role = $role
  $elastic_cluster_name = $cluster_name
  file { '/etc/elasticsearch/elasticsearch.yml':
    ensure  => file,
    content => template('profile/elasticsearch.yml.erb'),
    notify  => Service['elasticsearch'],
  }
}
