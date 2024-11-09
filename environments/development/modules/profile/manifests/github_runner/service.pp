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
