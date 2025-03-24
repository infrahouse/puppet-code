# @summary: downloads and extract actions-runner.
class profile::github_runner::package (
  $runner_package_directory,
  $runner_package_full_path,
  $package_directory_owner,
  $package_directory_group,
) {

  exec { 'download_runner_package':
    path    => '/usr/bin:/usr/local/bin',
    command => "ih-github runner download ${runner_package_full_path}",
    cwd     => '/var/tmp',
    creates => $runner_package_full_path,
    notify  => Exec['extract_runner_package']
  }

  file { $runner_package_directory:
    ensure => directory,
    owner  => $package_directory_owner,
    group  => $package_directory_group,
  }

  exec { 'extract_runner_package':
    path    => '/usr/bin',
    command => "tar xf ${runner_package_full_path} -C ${runner_package_directory}",
    require => File[$runner_package_directory],
    creates => "${runner_package_directory}/config.sh",
  }

  $enhancers = [
    'nodejs',
    'osv-scanner',
    'unzip',
    'yamllint',
  ]
  package { $enhancers: ensure => 'installed' }
}
