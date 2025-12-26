# Provides comprehensive system auditing for SOC2/ISO27001 compliance
#
# @param log_file Path to the audit log file
# @param log_file_mode File permissions for the audit log (e.g., '0640')
# @param log_file_owner Owner of the audit log file
# @param log_file_group Group owner of the audit log file
#
# @example Override via Hiera
#   profile::auditd::log_file: '/custom/audit/app.log'
#   profile::auditd::log_file_mode: '0600'
#   profile::auditd::log_file_owner: 'audituser'
#   profile::auditd::log_file_group: 'auditgroup'
#
class profile::auditd (
  String $log_file       = '/var/log/audit/audit.log',
  String $log_file_mode  = '0640',
  String $log_file_owner = 'root',
  String $log_file_group = 'adm',
) {

  package { 'auditd':
    ensure => installed,
  }

  package { 'audispd-plugins':
    ensure => installed,
  }

  # Main auditd configuration
  file { '/etc/audit/auditd.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => template('profile/auditd/auditd.conf.erb'),
    notify  => Service['auditd'],
    require => Package['auditd'],
  }

  # Base audit rules that apply to ALL systems
  file { '/etc/audit/rules.d/00-base.rules':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => template('profile/auditd/base.rules.erb'),
    notify  => Exec['augenrules'],
    require => Package['auditd'],
  }

  # Compliance-specific rules (SOC2, ISO27001)
  file { '/etc/audit/rules.d/10-compliance.rules':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => template('profile/auditd/compliance.rules.erb'),
    notify  => Exec['augenrules'],
    require => Package['auditd'],
  }

  # Remove static audit.rules file (conflicts with augenrules dynamic mode)
  file { '/etc/audit/rules.d/audit.rules':
    ensure => absent,
    notify => Exec['augenrules'],
  }

  # Apply audit rules
  exec { 'augenrules':
    command     => '/sbin/augenrules --load',
    refreshonly => true,
  }

  # Manage auditd service
  service { 'auditd':
    ensure    => running,
    enable    => true,
    restart   => '/usr/sbin/service auditd restart',
    subscribe => [
      File['/etc/audit/rules.d/00-base.rules'],
      File['/etc/audit/rules.d/10-compliance.rules'],
    ],
    require   => [
      Package['auditd'],
      File['/etc/audit/auditd.conf'],
    ],
  }

  # Ensure audit log file has correct permissions (0640 for compliance)
  file { $log_file:
    ensure  => file,
    owner   => $log_file_owner,
    group   => $log_file_group,
    mode    => $log_file_mode,
    require => Service['auditd'],
  }

  # Log rotation for audit logs
  file { '/etc/logrotate.d/audit':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('profile/auditd/logrotate.erb'),
  }
}
