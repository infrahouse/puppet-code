# @summary: Elasticsearch data node.
class profile::elastic_data () {

  include 'profile::elastic::repo'
  include 'profile::elastic::packages'
  include 'profile::elastic::service'
  include 'profile::elastic::kibana_user'
  include 'profile::elastic::backups'

  class { 'profile::elastic::config':
    role         => 'data',
  }
}
