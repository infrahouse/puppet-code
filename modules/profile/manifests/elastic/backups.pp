# @summary: Creates a cronjob to take regular snapshots.
class profile::elastic::backups () {

  cron { 'elastic-backup':
    command => '/usr/local/bin/ih-elastic snapshots status backups',
    user    => 'root',
    hour    => fqdn_rand(23),
    minute  => fqdn_rand(60),
  }
}
