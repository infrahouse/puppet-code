# @summary: Puppet role for an OpenVPN server
class role::openvpn_server () {

  include 'profile::base'
  include 'profile::openvpn_server'

  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
