# @summary: Installs elasicsearch service.
class profile::elastic::service (
  $mailto = lookup(
    'profile::cron::mailto', undef, undef, "root@${facts['networking']['hostname']}.${facts['networking']['domain']}"
  ),
  $decom_wait_time = lookup(
    'profile::elastic::service::decom_wait_time', undef, undef, 3600
  ),
) {

  include 'profile::letsencrypt'

  exec { 'reload-systemd-for-elastic':
    path        => '/bin',
    command     => 'systemctl daemon-reload',
    refreshonly => true,
    subscribe   => Package['elasticsearch'],
    notify      => Service['elasticsearch'],
  }

  $bootstrap_password = $facts['elasticsearch']['elastic_secret']
  $bootstrap_touch_file = '/etc/elasticsearch/.bootstrap_password_set'

  $bootstrap_password_script = '/usr/local/bin/set_bootstrap_password.sh'

  # Read bootstrap password from AWS secret $facts['elasticsearch']['elastic_secret']
  # Save it in the keystore. When saved, create file $bootstrap_touch_file
  # Run the script before Elasticsearch starts.
  file { $bootstrap_password_script:
    ensure  => file,
    mode    => '0755',
    content => template('profile/elasticsearch/set_bootstrap_password.sh'),
    require => [
      Package['elasticsearch'],
    ],
  }

  exec { 'set-bootstrap-password':
    command => $bootstrap_password_script,
    creates => $bootstrap_touch_file,
    require => File[$bootstrap_password_script],
  }

  service { 'elasticsearch':
    ensure    => running,
    subscribe => [
      File['/etc/elasticsearch/elasticsearch.yml'],
    ],
    require   => [
      Exec['set-bootstrap-password'],
      File['/etc/elasticsearch/elasticsearch.yml'],
    ]
  }

  # If node is about to be replaced by instance refresh
  # decommission it, wait until Elasticsearch moves shards out,
  # and complete a lifecycle hook.
  cron { 'decommission-node':
    command     => [
      'ih-elastic',
      '--quiet',
      'cluster',
      'decommission-node',
      '--only-if-terminating',
      '--reason',
      'instance_refresh',
      '--complete-lifecycle-action',
      '--wait-until-complete',
      $decom_wait_time,
    ].join(' '),
    environment => [
      'PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin',
      "MAILTO=${mailto}"
    ],
    user        => 'root',
    minute      => '*/5',
  }
}
