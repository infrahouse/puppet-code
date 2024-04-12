# @summary: creates a unix user/group
class profile::github_runner::user (
  $user,
  $group,
  $home,
  $docker_package = 'docker-ce',
) {

  group { $user:
    ensure => present,
  }

  user { $user:
    ensure  => present,
    gid     => $group,
    home    => $home,
    shell   => '/bin/bash',
    require => Package[$docker_package],
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
