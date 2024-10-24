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

}
