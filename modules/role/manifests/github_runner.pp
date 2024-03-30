# @summary: Puppet role for a github_runner
class role::github_runner () {

  include 'profile::base'
  include 'profile::github_runner'

}
