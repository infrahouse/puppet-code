# @summary: Puppet role for a Percona Server node
class role::percona_server () {

  include 'profile::base'
  include 'profile::percona'

}