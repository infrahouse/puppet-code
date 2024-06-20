# @summary: Puppet role for an elasticsearch node
class role::elastic_data () {

  include 'profile::base'
  include 'profile::elastic_data'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}

