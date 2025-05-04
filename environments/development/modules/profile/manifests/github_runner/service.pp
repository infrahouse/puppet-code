# @summary: runs the actions_runner servi e.
class profile::github_runner::service (
  $runner_package_directory,
  $user,
  $group,
  $mailto = lookup(
    'profile::cron::mailto', undef, undef, "root@${facts['networking']['hostname']}.${facts['networking']['domain']}"
  ),
  $disk_usage_threshold = lookup(
    'profile::github_runner::service::disk_usage_threshold', undef, undef, 80
  ),
) {

  $github_runner_user = $user
  $github_runner_group = $group
  $systemd_file = '/etc/systemd/system/actions-runner.service'
  $start_script = '/usr/local/bin/start-actions-runner.sh'
  $env_file = "${runner_package_directory}/.env"
  $cleanup_path = '/usr/local/bin/gha_cleanup.sh'

  file { $env_file:
    ensure  => file,
    content => "ACTIONS_RUNNER_HOOK_JOB_STARTED=${cleanup_path}\n",
    owner   => $user,
    group   => $group,
    mode    => '0644',
    notify  => Service['actions-runner'],
    require => [
      File[$runner_package_directory],
      Exec['extract_runner_package'],
    ]
  }

  file { '/etc/sudoers.d/github_runner_chmod':
    ensure  => file,
    mode    => '0440',
    owner   => 'root',
    group   => 'root',
    content => "github-runner ALL=(ALL) NOPASSWD: /usr/bin/chown\n",
  }

  file { $cleanup_path:
    ensure => file,
    source => 'puppet:///modules/profile/github_runner/gha_cleanup.sh',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $start_script:
    ensure  => file,
    content => template('profile/github_runner/start-actions-runner.sh.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0755',
  }

  file { $systemd_file:
    ensure  => file,
    content => template('profile/github_runner/actions-runner.service.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
    notify  => Exec['daemon-reload'],
  }

  exec { 'daemon-reload':
    command     => '/usr/bin/systemctl daemon-reload',
    refreshonly => true,
  }

  service { 'actions-runner':
    ensure  => running,
    require => [
      File[$systemd_file],
      File[$start_script],
      File[$env_file],
      Exec['daemon-reload'],
    ]
  }

  cron { 'check-health':
    command     => [
      'ih-github',
      'runner',
      'check-health',
      '--disk-usage-threshold',
      $disk_usage_threshold,
    ].join(' '),
    environment => [
      'PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin',
      "MAILTO=${mailto}"
    ],
    user        => 'root',
    minute      => '*/5',
  }
}
