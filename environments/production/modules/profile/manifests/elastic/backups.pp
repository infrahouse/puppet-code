# @summary: Creates a cronjob to take regular snapshots.
class profile::elastic::backups (
  Any $hour = lookup(
    'profile::elastic::backups::hour',
    undef,
    undef,
    fqdn_rand(24)
  ),
  Any $minute = lookup(
    'profile::elastic::backups::minute',
    undef,
    undef,
    fqdn_rand(60)
  )
) {

  cron { 'elastic-backup':
    command => '/usr/local/bin/ih-elastic --quiet snapshots create backups',
    user    => 'root',
    hour    => $hour,
    minute  => $minute,
  }
}
