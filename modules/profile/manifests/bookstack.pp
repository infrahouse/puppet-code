# @summary: Installs bookstack applicartion
class profile::bookstack () {
  include 'profile::base'
  include 'profile::bookstack::packages'
  include 'profile::bookstack::service'
}
