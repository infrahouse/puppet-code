# Jumphost-specific auditd configuration
# Critical for SOC2/ISO27001 as jumphost is a privileged access point
class profile::jumphost::auditd {

  # Include the base auditd profile
  include profile::auditd

  # Deploy jumphost-specific audit rules
  file { '/etc/audit/rules.d/50-jumphost.rules':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => template('profile/jumphost/jumphost.rules.erb'),
    notify  => Exec['augenrules'],
    require => Package['auditd'],
  }
}
