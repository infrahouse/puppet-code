# @summary: Elasticsearch master node.
class profile::elastic_master () {

  include 'profile::elastic::repo'
  include 'profile::elastic::packages'
  include 'profile::elastic::service'

  class { 'profile::elastic::config':
    role         => 'master',
  }
}
