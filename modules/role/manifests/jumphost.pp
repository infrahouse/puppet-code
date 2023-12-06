# @summary: Puppet role for a jumphost
class role::jumphost () {

  include 'profile::base'
  include 'profile::ecs'

}
