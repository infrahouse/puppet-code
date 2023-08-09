# @summary: Configure cron job for periodic puppet apply.
class profile::puppet_apply () {

  package { 'puppet-code':
    ensure => latest
  }

  $m = fqdn_rand(30)
  cron { 'puppet_apply':
    command     => 'ih-puppet apply',
    environment => 'PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin',
    user        => 'root',
    minute      => [$m, $m + 30],
    require     => [
      Package['puppet-code'],
      Package['infrahouse-toolkit']
    ]
  }

}
