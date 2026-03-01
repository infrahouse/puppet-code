# @summary Manages the Percona Orchestrator service
class profile::percona::orchestrator::service () {
  service { 'orchestrator':
    ensure  => running,
    enable  => true,
    require => [Package['orchestrator'], File['/etc/orchestrator.conf.json']],
  }
}
