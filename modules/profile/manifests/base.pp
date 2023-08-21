# @summary: Base profile to be included by all roles.
class profile::base () {

  stage { 'init': before  => Stage['main'] }

  include 'profile::repos'
  include 'profile::packages'
  include 'profile::infrahouse_toolkit'
  include 'profile::puppet_apply'

}
