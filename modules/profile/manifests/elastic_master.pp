# @summary: Elasticsearch master node.
class profile::elastic_master () {

  include 'profile::elastic_master::repo'
  include 'profile::elastic_master::packages'
  include 'profile::elastic_master::service'

}
