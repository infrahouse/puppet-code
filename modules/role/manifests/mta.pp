# @summary: Puppet role for a MTA
class role::mta () {

  include 'profile::base'
  include 'profile::postfix'

}
