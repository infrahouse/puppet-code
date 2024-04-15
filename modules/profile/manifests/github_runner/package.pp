# @summary: downloads and extract actions-runner.
class profile::github_runner::package (
  $runner_package_full_path,
  $runner_package_directory,
  $package_directory_owner,
  $package_directory_group,
  $runner_package_url = lookup(
    'profile::github_runner::runner_package_url',
    undef,
    undef,
    'https://github.com/actions/runner/releases/download/v2.314.1/actions-runner-linux-x64-2.314.1.tar.gz'
  )
) {

  exec { 'download_runner_package':
    path    => '/usr/bin',
    command => "curl -o ${runner_package_full_path} -L ${runner_package_url}",
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

  ['.credentials', '.credentials_rsaparams', '.env', '.path', '.runner', '_diag'].each |$file_path| {
    file { "${runner_package_directory}/${file_path}":
      owner   => $package_directory_owner,
      group   => $package_directory_group,
      require => Exec['extract_runner_package']
    }
  }

  $enhancers = [
    'yamllint',
  ]
  package { $enhancers: ensure => 'installed' }
}
