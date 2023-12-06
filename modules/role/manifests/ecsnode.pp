# @summary: Puppet role for a ECS node
class role::ecsnode () {

  include 'profile::base'
  include 'profile::ecs'

}
