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
  # warm->hot transition either. Apply pending security upgrades ONCE here,
  # during provisioning, before the instance hibernates, so every runner enters
  # the warm pool already patched. Fresh launches (driven by the ASG's
  # max_instance_lifetime) re-run this on each new instance, which bounds how
  # stale a pooled instance can be. In-service runners keep getting the daily
  # timer (and profile::github_runner::service keeps that from cancelling jobs).
  #
  # The marker lives on tmpfs (/run, cleared on a real boot) so this runs once
  # per boot rather than on every Puppet apply, and is written only on success,
  # so a failed upgrade simply retries on the next apply. This applies Ubuntu
  # security updates, which do not depend on the InfraHouse repos.
  #
  # The retry/bounding logic lives in the script rather than in exec's
  # tries/try_sleep because exec's timeout is per-attempt, so tries would multiply
  # the worst case with no cumulative cap. A resource failure here ABANDONs the
  # instance (ih-puppet exits 4/6, ih-bootstrap's ERR trap signals ABANDON), so
  # the total must stay inside the 1200s bootstrap hook budget -- nothing renews
  # it, since gha-lifecycle-heartbeater.sh is a no-op outside Terminating:Wait.
  $boot_upgrade_script = '/usr/local/bin/gha-boot-security-upgrade.sh'
  $boot_upgrade_budget = 480

  file { $boot_upgrade_script:
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/profile/github_runner/gha-boot-security-upgrade.sh',
  }

  exec { 'gha-boot-security-upgrade':
    command => "${boot_upgrade_script} ${boot_upgrade_budget}",
    path    => '/usr/bin:/bin:/usr/sbin:/sbin',
    unless  => 'test -f /run/gha-boot-upgrade.done',
    # Slightly above the script's own budget so the script always gets to exit and
    # log why it gave up, rather than being killed mid-report by Puppet.
    timeout => $boot_upgrade_budget + 60,
    require => [
      Class['profile::unattended_upgrades'],
      File[$boot_upgrade_script],
    ],
  }

}
