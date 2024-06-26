# @summary: Puppet role for a ECS node
class role::openvpn_server () {

  include 'profile::base'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
