# @summary: Puppet role for a infrahouse_github_backup
class role::infrahouse_github_backup () {

  include 'profile::base'
  include 'profile::infrahouse_github_backup'
  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
