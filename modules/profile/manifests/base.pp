class profile::base () {

  include 'profile::repos'
  include 'profile::packages'
  include 'profile::infrahouse_toolkit'
  include 'profile::puppet_apply'

}
