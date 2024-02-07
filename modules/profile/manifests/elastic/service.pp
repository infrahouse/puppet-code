# @summary: Installs elasicsearch service.
class profile::elastic::service () {

  exec { 'reload-systemd-for-elastic':
    path        => '/bin',
    command     => 'systemctl daemon-reload',
    refreshonly => true,
    subscribe   => Package['elasticsearch'],
    notify      => Service['elasticsearch'],
  }

  service { 'elasticsearch':
    ensure  => running,
    subscribe => [
      File['/etc/elasticsearch/elasticsearch.yml'],
    ],
    require => [
      File['/etc/elasticsearch/elasticsearch.yml'],
    ]
  }
}
