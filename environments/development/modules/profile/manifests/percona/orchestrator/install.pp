# @summary Installs Percona Orchestrator package
class profile::percona::orchestrator::install () {
  package { 'orchestrator':
    ensure => 'installed',
  }

  package { 'orchestrator-client':
    ensure => 'installed',
  }
}
