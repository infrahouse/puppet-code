# @summary: Installs OpenVPN server config.
class profile::openvpn_server::nat (
) {
  file { '/etc/sysctl.d/net.ipv4.ip_forward.conf':
    content => 'net.ipv4.ip_forward = 1',
    notify  => Exec[deb_systemd_invoke_restart_procps_service],
  }

  exec {'deb_systemd_invoke_restart_procps_service':
    path        => '/usr/bin',
    command     => 'deb-systemd-invoke restart procps.service',
    refreshonly => true,
  }

  package { 'iptables-persistent':
    ensure => present,
  }

  firewall { '100 NAT for OpenVPN':
    chain    => 'POSTROUTING',
    table    => 'nat',
    outiface => $facts['networking']['primary'],
    jump     => 'MASQUERADE',
    require  => Package[iptables-persistent],
  }

}
