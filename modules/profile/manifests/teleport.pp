# @summary: Configures single node Teleport
class profile::teleport () {
  class { 'profile::teleport::config':

  }
  include 'profile::teleport::packages'
  include 'profile::teleport::service'

}
