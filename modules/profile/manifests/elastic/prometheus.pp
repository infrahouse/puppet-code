# @summary: Installs Prometheus Node exporter.
class profile::elastic::prometheus (
) {

  package { 'prometheus-node-exporter':
    ensure  => present,
  }

  service { 'prometheus-node-exporter':
    ensure  => running,
    require => Package['prometheus-node-exporter'],
  }

  $user = 'elastic'
  $password = aws_get_secret(
      $facts['elasticsearch']['elastic_secret'],
      $facts['ec2_metadata']['placement']['region']
    )
  $ip = $facts['networking']['ip']

  file { '/etc/prometheus-elasticsearch-exporter.conf':
    ensure  => file,
    mode    => '0600',
    content => template('profile/elasticsearch/prometheus-elasticsearch-exporter.erb'),
    notify  => Service['prometheus-elasticsearch-exporter'],
  }

  file { '/lib/systemd/system/prometheus-elasticsearch-exporter.service':
    ensure  => file,
    source  => 'puppet:///modules/profile/elastic_master/prometheus-elasticsearch-exporter.service',
    notify  => Exec['reload-systemd-prometheus-elasticsearch-exporter'],
    require => Package['prometheus-elasticsearch-exporter'],
  }

  exec { 'reload-systemd-prometheus-elasticsearch-exporter':
    path        => '/bin',
    command     => 'systemctl daemon-reload',
    refreshonly => true,
    subscribe   => File['/lib/systemd/system/prometheus-elasticsearch-exporter.service'],
    notify      => Service['prometheus-elasticsearch-exporter'],
  }

  package { 'prometheus-elasticsearch-exporter':
    ensure  => present,
  }

  service { 'prometheus-elasticsearch-exporter':
    ensure  => running,
    require => Package['prometheus-elasticsearch-exporter'],
  }

}
