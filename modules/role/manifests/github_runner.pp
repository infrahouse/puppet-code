# @summary: Puppet role for a github_runner
class role::github_runner () {

  include 'profile::base'
  include 'profile::github_runner'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
