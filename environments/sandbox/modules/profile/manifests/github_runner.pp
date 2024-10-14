# @summary: github_runner profile.
class profile::github_runner (
  $url = lookup('profile::github_runner::url'),
  $org = lookup('profile::github_runner::org'),
  $runner_labels = lookup(
    'profile::github_runner::labels',
    undef,
    undef,
    []
  ),
) {

  $tmp_dir = '/tmp'
  $runner_package_file = 'actions-runner-linux.tar.gz'
  $runner_package_full_path = "${tmp_dir}/${runner_package_file}"
  $runner_package_directory = "${tmp_dir}/actions-runner-linux"

  $user = 'github-runner'
  $group = 'docker'
  require 'profile::docker'

  class { 'profile::github_runner::user':
    user  => $user,
    group => $group,
    home  => $runner_package_directory,
  }

  class { 'profile::github_runner::package':
    runner_package_directory => $runner_package_directory,
    runner_package_full_path => $runner_package_full_path,
    package_directory_owner  => $user,
    package_directory_group  => $group,
  }

  $registration_token_secret_prefix = $facts['registration_token_secret_prefix']
  $instance_id = $facts['ec2_metadata']['instance-id']
  $token_secret = "${registration_token_secret_prefix}-${instance_id}"

  class { 'profile::github_runner::register':
    runner_labels            => $runner_labels,
    runner_package_directory => $runner_package_directory,
    token_secret             => $token_secret,
    org                      => $org,
    url                      => $url,
    user                     => $user,
  }

  class { 'profile::github_runner::service':
    runner_package_directory => $runner_package_directory,
    user                     => $user,
    group                    => $group,
  }

}
