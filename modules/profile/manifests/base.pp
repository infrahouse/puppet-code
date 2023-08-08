class profile::base () {

  include 'profile::apt'
  include 'profile::infrahouse_toolkit'
  include 'profile::puppet_apply'

}
