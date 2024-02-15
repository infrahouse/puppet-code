# @summary: Installs elasicsearch service.
class profile::elastic::service () {

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
}
