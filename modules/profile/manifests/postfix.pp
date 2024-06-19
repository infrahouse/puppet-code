# @summary: Postfix profile.
class profile::postfix (
  $postfix_inet_interfaces = 'all'
) {
  include 'profile::postfix::packages'
  include 'profile::postfix::service'

  class { 'profile::postfix::config':
    postfix_inet_interfaces => $postfix_inet_interfaces
  }

}
