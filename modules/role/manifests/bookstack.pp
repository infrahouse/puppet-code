# @summary: Puppet role for a jumphost
class role::bookstack () {

  include 'profile::bookstack'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }

}
