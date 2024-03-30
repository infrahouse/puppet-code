# @summary: github_runner profile.
class profile::github_runner (
  $url = lookup('profile::github_runner::url'),
  $org = lookup('profile::github_runner::org'),
  $token_secret = lookup(
    'profile::github_runner::github_token_secret',
    undef,
    undef,
    'GITHUB_TOKEN'
  ),
  $runner_labels = lookup(
    'profile::github_runner::labels',
    undef,
    undef,
    []
  ),
  $runner_package_url = lookup(
    'profile::github_runner::runner_package_url',
    undef,
    undef,
    'https://github.com/actions/runner/releases/download/v2.314.1/actions-runner-linux-x64-2.314.1.tar.gz'
  )
) {
  $tmp_dir = '/tmp'
  $runner_package_file = 'actions-runner-linux.tar.gz'
  $runner_package_full_path = "${tmp_dir}/${runner_package_file}"
  $runner_package_directory = "${tmp_dir}/actions-runner-linux"
  $hostname = $facts['networking']['hostname']

  exec { 'download_runner_package':
    path    => '/usr/bin',
    command => "curl -o ${runner_package_full_path} -L ${runner_package_url}",
    creates => $runner_package_full_path,
    notify  => Exec['extract_runner_package']
  }

  file { $runner_package_directory:
    ensure => directory
  }

  file { '/usr/local/bin/register_github_runner.sh':
    ensure => absent,
  }

  exec { 'extract_runner_package':
    path    => '/usr/bin',
    command => "tar xf ${runner_package_full_path} -C ${runner_package_directory}",
    require => File[$runner_package_directory],
    creates => "${runner_package_directory}/config.sh",
  }

  $labels = $runner_labels.map |$label| {
    "--label ${label}"
  }
  $labels_arg = join($labels, ' ')
  exec { 'register_runner':
    path    => "/usr/bin:/usr/local/bin:${runner_package_directory}",
    cwd     => $runner_package_directory,
    command => "ih-github runner --github-token-secret ${token_secret} --org ${org} register \
--actions-runner-code-path ${runner_package_directory} ${url} ${labels_arg}",
    unless  => "ih-github runner --github-token-secret ${token_secret} --org ${org} is-registered ${hostname}",
    require => [
      Exec[extract_runner_package]
      ]
  }
}
