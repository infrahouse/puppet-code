# @summary: Puppet role for an elasticsearch node
class role::elastic_master () {

  include 'profile::base'
  include 'profile::elastic_master'
}

