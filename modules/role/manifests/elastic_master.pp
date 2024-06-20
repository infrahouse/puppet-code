# @summary: Puppet role for an elasticsearch node
class role::elastic_master () {

  include 'profile::base'
  include 'profile::elastic_master'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}

