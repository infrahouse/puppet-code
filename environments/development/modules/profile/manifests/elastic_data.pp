# @summary: Elasticsearch data node.
class profile::elastic_data () {

  include 'profile::elastic::packages'
  include 'profile::elastic::service'
  include 'profile::elastic::kibana_user'
  include 'profile::elastic::prometheus'
  include 'profile::elastic::tls'

  class { 'profile::elastic::backups':
    snapshot_policy_path => '/etc/elasticsearch/snapshot-policy.json',
  }

  class { 'profile::elastic::config':
    role => lookup(
      'profile::elastic::config::role',
      undef,
      undef,
      'data'
    ),
  }
}
