# Provides comprehensive system auditing for SOC2/ISO27001 compliance
class profile::auditd {

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

  # Apply audit rules
  exec { 'augenrules':
    command     => '/sbin/augenrules --load',
    refreshonly => true,
    notify      => Service['auditd'],
  }

  # Manage auditd service
  service { 'auditd':
    ensure  => running,
    enable  => true,
    require => [
      Package['auditd'],
      File['/etc/audit/auditd.conf'],
    ],
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
