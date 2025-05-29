# @summary: Puppet role for teleport
class role::teleport () {

  include 'profile::base'
  include 'profile::teleport'
}
