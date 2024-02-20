# @summary: Creates a cronjob to take regular snapshots.
class profile::elastic::backups () {

  cron { 'elastic-backup':
    command => '/usr/local/bin/ih-elastic snapshots create backups',
    user    => 'root',
    hour    => fqdn_rand(24),
    minute  => fqdn_rand(60),
  }
}
