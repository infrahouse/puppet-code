# @summary: Postfix profile.
class profile::postfix (
) {
  include 'profile::postfix::packages'
  include 'profile::postfix::config'
  include 'profile::postfix::service'

}
