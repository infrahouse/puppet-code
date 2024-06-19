# @summary: Puppet role for a jumphost
class role::jumphost () {

  include 'profile::base'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
