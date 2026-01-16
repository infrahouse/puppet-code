# Terraformer-specific auditd configuration
# Tracks all Terraform command execution for compliance and audit trail
class profile::terraformer::auditd {

  # Include the base auditd profile
  include profile::auditd

  # Deploy terraformer-specific audit rules
  file { '/etc/audit/rules.d/50-terraformer.rules':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => template('profile/terraformer/terraformer.rules.erb'),
    notify  => Exec['augenrules'],
    require => Package['auditd'],
  }
}