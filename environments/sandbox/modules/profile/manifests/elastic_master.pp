# @summary: Elasticsearch master node.
class profile::elastic_master () {

  include 'profile::elastic::packages'
  include 'profile::elastic::service'
  include 'profile::elastic::prometheus'

  class { 'profile::elastic::config':
    role         => 'master, remote_cluster_client',
  }
}
