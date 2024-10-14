# @summary: Installs and configures infrahouse-toolkit.
class profile::infrahouse_toolkit () {
  package { 'infrahouse-toolkit':
    ensure => latest
  }
}
