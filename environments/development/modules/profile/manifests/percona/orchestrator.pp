# @summary Installs and configures Percona Orchestrator
class profile::percona::orchestrator () {
  include profile::percona::orchestrator::install
  include profile::percona::orchestrator::config
  include profile::percona::orchestrator::service
}
