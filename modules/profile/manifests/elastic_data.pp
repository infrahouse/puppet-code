# @summary: Elasticsearch data node.
class profile::elastic_data () {

  include 'profile::elastic::repo'
  include 'profile::elastic::packages'
  include 'profile::elastic::service'

  class { 'profile::elastic::config':
    role         => 'data',
    cluster_name => lookup('elasticsearch::cluster::name', undef, undef, 'elasticsearch'),
  }
}
