# @summary: Installs elasicsearch service.
class profile::elastic_master::service () {

  file { '/etc/elasticsearch/elasticsearch.yml':
    ensure  => file,
    content => template('profile/elasticsearch.yml.erb'),
    notify  => Service['elasticsearch'],
  }

  exec { 'reload-systemd-for-elastic':
    path        => '/bin',
    command     => 'systemctl daemon-reload',
    refreshonly => true,
    subscribe   => Package['elasticsearch'],
    notify      => Service['elasticsearch'],
  }

  service { 'elasticsearch':
    ensure  => running,
    require => [
      File['/etc/elasticsearch/elasticsearch.yml'],
    ]
  }
}
