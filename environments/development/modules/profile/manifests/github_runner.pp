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

  # Warm-pool runners are HIBERNATED right after provisioning, so the daily
  # unattended-upgrades timer never runs while they sit in the pool -- and a
  # hibernation resume is not a boot, so systemd boot units do not re-run on the
  # warm->hot transition either. profile::boot_security_upgrade applies pending
  # security upgrades ONCE here, during provisioning, before the instance
  # hibernates, so every runner enters the warm pool already patched. Fresh
  # launches (driven by the ASG's max_instance_lifetime) re-run it on each new
  # instance, which bounds how stale a pooled instance can be. In-service runners
  # keep getting the daily timer (and profile::github_runner::service keeps that
  # from cancelling jobs).
  #
  # Declared resource-like rather than through hiera because both values below
  # follow from this role's ASG lifecycle, not from site policy:
  #
  #   budget        A resource failure here ABANDONs the instance (ih-puppet exits
  #                 4/6, ih-bootstrap's ERR trap signals ABANDON), so the total
  #                 must stay inside the 1200s bootstrap hook budget -- nothing
  #                 renews it, since gha-lifecycle-heartbeater.sh is a no-op
  #                 outside Terminating:Wait.
  #
  #   fail_on_error Runners are disposable: a host that could not patch should be
  #                 abandoned and replaced, not kept. That is the opposite of the
  #                 default, which suits stateful roles where an unpatched-but-
  #                 running host beats no host.
  class { 'profile::boot_security_upgrade':
    budget        => 480,
    fail_on_error => true,
  }

}
