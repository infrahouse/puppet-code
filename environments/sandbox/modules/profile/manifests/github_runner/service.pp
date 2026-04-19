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
  $prerun_path = '/usr/local/bin/gha_prerun.sh'
  $postrun_path = '/usr/local/bin/gha_postrun.sh'
  $on_exit_path = '/usr/local/bin/gha-on-runner-exit.sh'
  $heartbeater_script = '/usr/local/bin/gha-lifecycle-heartbeater.sh'
  $heartbeater_service = '/etc/systemd/system/gha-lifecycle-heartbeater.service'
  $heartbeater_timer = '/etc/systemd/system/gha-lifecycle-heartbeater.timer'
  $deregistration_hookname = pick_default($facts['deregistration_hookname'], '')

  file { $env_file:
    ensure  => file,
    content => template('profile/github_runner/actions_env.erb'),
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

  file { $prerun_path:
    ensure => file,
    source => 'puppet:///modules/profile/github_runner/gha_prerun.sh',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $postrun_path:
    ensure => file,
    source => 'puppet:///modules/profile/github_runner/gha_postrun.sh',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $on_exit_path:
    ensure => file,
    source => 'puppet:///modules/profile/github_runner/gha-on-runner-exit.sh',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $heartbeater_script:
    ensure => file,
    source => 'puppet:///modules/profile/github_runner/gha-lifecycle-heartbeater.sh',
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

  file { $heartbeater_service:
    ensure  => file,
    content => template('profile/github_runner/gha-lifecycle-heartbeater.service.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    notify  => Exec['daemon-reload'],
  }

  file { $heartbeater_timer:
    ensure => file,
    source => 'puppet:///modules/profile/github_runner/gha-lifecycle-heartbeater.timer',
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    notify => Exec['daemon-reload'],
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

  service { 'gha-lifecycle-heartbeater.timer':
    ensure  => running,
    enable  => true,
    require => [
      File[$heartbeater_script],
      File[$heartbeater_service],
      File[$heartbeater_timer],
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
