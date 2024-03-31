# @summary: creates a unix user/group
class profile::github_runner::user (
  $user,
  $group,
  $home
) {

  group { $user:
    ensure => present,
  }

  user { $user:
    ensure => present,
    gid    => $group,
    home   => $home,
    shell  => '/bin/bash',
  }

  $aws_region = $facts['ec2_metadata']['placement']['region']

  file { "${home}/.aws":
    ensure  => directory,
    owner   => $user,
    group   => $group,
    require => User[$user],
  }

  file { "${home}/.aws/config":
    ensure  => present,
    content => "[default]\nregion=${aws_region}",
    owner   => $user,
    group   => $group,
    require => File["${home}/.aws"],
  }
}
