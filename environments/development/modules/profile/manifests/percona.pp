# @summary: Installs Percona Server and related components
class profile::percona () {

  include 'profile::percona::repo'

}