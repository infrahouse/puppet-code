# @summary: Configure infrahouse_github_backup GuitHub App.
class profile::infrahouse_github_backup (
  $app_key_url = lookup(
    'profile::infrahouse_github_backup::app_key_url',
    undef,
    undef,
    $facts['infrahouse-github-backup']['app-key-url']
  ),
  $mailto = lookup(
    'profile::infrahouse_github_backup::mailto', undef, undef,
    "root@${facts['networking']['hostname']}.${facts['networking']['domain']}"
  )
) {

  file { '/etc/apt/keyrings/githubcli-archive-keyring.gpg':
    source => 'puppet:///modules/profile/githubcli-archive-keyring.gpg',
    mode   => 'a+r',
  }

  file { '/etc/apt/sources.list.d/githubcli.list':
    ensure  => file,
    content => template('profile/githubcli.list.erb'),
    notify  => Exec['profile::infrahouse_github_backup::apt_update'],
  }

  exec { 'profile::infrahouse_github_backup::apt_update':
    command     => ['apt-get', 'update'],
    path        => ['/usr/bin', '/usr/sbin',],
    refreshonly => true,
  }

  package { [
    'gh',
  ]:
    ensure  => latest,
    require => [
      File['/etc/apt/sources.list.d/githubcli.list'],
      Exec['profile::infrahouse_github_backup::apt_update'],
    ]
  }

  cron { 'infrahouse_github_backup':
    command     => [
    'ih-github',
    'backup',
    '--app-key-url',
      $app_key_url,
    '--tmp-volume-size',
      $facts['memory']['system']['total_bytes'],
    ].join(' '),
    environment => [
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      "MAILTO=${mailto}"
    ],
    user        => 'root',
    hour        => '0',
    minute      => '0',
  }
}
