class profile::puppet_apply () {

  $puppet_apply_binary = '/usr/local/sbin/puppet_apply'
  file { $puppet_apply_binary:
    source => 'puppet:///modules/profile/puppet_apply.sh',
    mode   => '0755',
    owner  => 'root',

  }
  $m = fqdn_rand(30)
  cron { 'puppet_apply':
    command => $puppet_apply_binary,
    user    => 'root',
    minute  => [$m, $m + 30],
    require => [
      File[$puppet_apply_binary],
    ]
  }

}
