# @summary: Base profile to be included by all roles.
class profile::base () {

  stage { 'init': before  => Stage['main'] }

  include 'profile::repos'
  include 'profile::packages'
  include 'profile::infrahouse_toolkit'
  include 'profile::puppet_apply'
  include 'profile::swap'
  include '::accounts'
  include '::sudo'

  # Install puppet gems
  $gems = [
    'json', 'aws-sdk-core', 'aws-sdk-secretsmanager'
  ]

  $gem_cmd = '/opt/puppetlabs/puppet/bin/gem'
  $gems.each |$gem| {
    exec { "gem_install_${gem}":
      command => "${gem_cmd} install ${gem}",
      path    => '/bin:/usr/bin',
      unless  => "${gem_cmd} list | grep ${gem}",
    }
  }

}
