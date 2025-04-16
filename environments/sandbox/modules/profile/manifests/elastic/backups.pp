# @summary: Creates a cronjob to take regular snapshots.
class profile::elastic::backups (
  String $snapshot_policy_path,
) {

  cron { 'elastic-backup':
    ensure  => absent,
    command => '/usr/local/bin/ih-elastic --quiet snapshots create backups',
    user    => 'root',
  }
  exec { 'sync-snapshot-policy':
    command     => "/usr/local/bin/ih-elastic snapshots policy ${snapshot_policy_path}",
    refreshonly => true,
    require     => Service[elasticsearch],
  }

  file { $snapshot_policy_path:
    ensure  => file,
    content => template('profile/elasticsearch/snapshot-policy.json'),
    require => [
      Package['elasticsearch']
    ],
    notify  => Exec[sync-snapshot-policy],
  }

}
