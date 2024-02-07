# @summary: Puppet role for an elasticsearch node
class role::elastic_data () {

  include 'profile::base'
  include 'profile::elastic_data'
}

