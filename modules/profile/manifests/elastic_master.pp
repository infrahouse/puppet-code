# @summary: Elasticsearch master node.
class profile::elastic_master () {

  include 'profile::elastic::packages'
  include 'profile::elastic::service'
  include 'profile::elastic::prometheus'
  include 'profile::elastic::tls'

  $role = $facts['elasticsearch']['bootstrap_cluster'] ? {
    true  => 'master, remote_cluster_client, data',
    false => 'master, remote_cluster_client',
  }

  class { 'profile::elastic::config':
    role => $role,
  }
}
