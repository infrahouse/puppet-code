# @summary: Puppet role for a terraformer instance
class role::terraformer () {

  include 'profile::base'
  include 'profile::terraformer'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
