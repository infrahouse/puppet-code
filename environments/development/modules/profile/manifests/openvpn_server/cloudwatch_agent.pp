# @summary: Manages CloudWatch Logs Agent for OpenVPN server.
#
# This class configures the CloudWatch agent for OpenVPN by including
# the shared base class with OpenVPN-specific log collection.
#
# OpenVPN-specific logs:
# - /var/log/openvpn/openvpn.log - VPN server logs
#
# OpenVPN-specific procstat:
# - openvpn - Monitor OpenVPN process
#
class profile::openvpn_server::cloudwatch_agent {

  # Only manage CloudWatch agent if the cloudwatch_log_group fact is present
  # This fact is provided by Terraform in custom_facts
  if $facts['openvpn'] and $facts['openvpn']['cloudwatch_log_group'] {

    # Include shared CloudWatch agent base class with OpenVPN-specific extras
    class { 'profile::cloudwatch_agent':
      cloudwatch_log_group => $facts['openvpn']['cloudwatch_log_group'],
      cloudwatch_namespace => pick($facts['openvpn']['cloudwatch_namespace'], 'OpenVPN/System'),
      extra_logs           => [
        { 'path' => '/var/log/openvpn/openvpn.log', 'stream' => 'openvpn/server' },
      ],
      extra_procstat       => ['openvpn'],
    }

    # ACL package needed for setfacl command
    package { 'acl':
      ensure => installed,
    }

    # Scripts to manage ACLs on OpenVPN log files
    file { '/usr/local/bin/set-openvpn-acl':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => template('profile/openvpn_server/set-openvpn-acl.sh.erb'),
      require => Class['profile::cloudwatch_agent'],
    }

    file { '/usr/local/bin/check-openvpn-acl':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => template('profile/openvpn_server/check-openvpn-acl.sh.erb'),
      require => Class['profile::cloudwatch_agent'],
    }

    # Allow CloudWatch agent to read OpenVPN logs
    exec { 'set-openvpn-log-acl':
      command => '/usr/local/bin/set-openvpn-acl',
      unless  => '/usr/local/bin/check-openvpn-acl',
      require => [
        Package['acl'],
        File['/usr/local/bin/set-openvpn-acl'],
        File['/usr/local/bin/check-openvpn-acl'],
      ],
    }

    # Logrotate configuration for OpenVPN logs
    # Reference: https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html
    file { '/etc/logrotate.d/openvpn':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('profile/openvpn_server/logrotate.erb'),
      require => File['/usr/local/bin/set-openvpn-acl'],
    }

  }

}
