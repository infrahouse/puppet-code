# @summary: Installs Percona Server and related components
class profile::percona () {

  include 'profile::percona::repo'
  include 'profile::percona::packages'
  include 'profile::percona::config'
  include 'profile::percona::service'
  include 'profile::percona::bootstrap'

}
