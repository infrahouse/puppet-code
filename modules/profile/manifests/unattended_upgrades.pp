# @summary: Enable unattended-upgrades fleet-wide for automatic security updates.
#
# Included by profile::base so every host receives security fixes. The base
# AMI ships the relevant systemd units masked; this profile unmasks and enables
# them and owns their configuration via Puppet.
#
# Hosts that must not be disrupted by an automatic service restart (e.g.
# Elasticsearch nodes) keep unattended-upgrades running but blacklist the
# sensitive package(s) through $package_blacklist (set per-role in Hiera) and
# suppress automatic restarts separately (see profile::elastic::service).
class profile::unattended_upgrades (
  Boolean       $automatic_reboot  = lookup('profile::unattended_upgrades::automatic_reboot', undef, undef, false),
  Array[String] $package_blacklist = lookup('profile::unattended_upgrades::package_blacklist', undef, undef, []),
) {

  package { 'unattended-upgrades':
    ensure => present,
  }

  # Units that drive automatic upgrades:
  #   - the timers run the periodic download + upgrade
  #   - unattended-upgrades.service applies pending upgrades on shutdown/boot
  # The base AMI ships these masked. A masked apt-daily.service also prevents
  # its timer from starting ("unit to trigger not loaded"), so the trigger
  # .service units must be unmasked too even though we never run them directly.
  # Puppet's service provider cannot unmask a unit, hence the execs.
  $unmask_units = [
    'unattended-upgrades.service',
    'apt-daily.service',
    'apt-daily.timer',
    'apt-daily-upgrade.service',
    'apt-daily-upgrade.timer',
  ]

  # Only the timers (periodic runs) and unattended-upgrades.service (apply on
  # shutdown) are actively enabled; apt-daily*.service are oneshots triggered
  # by their timers.
  $enabled_units = [
    'unattended-upgrades.service',
    'apt-daily.timer',
    'apt-daily-upgrade.timer',
  ]

  $unmask_units.each |$unit| {
    exec { "unmask-${unit}":
      command => "systemctl unmask ${unit}",
      path    => '/bin:/usr/bin:/sbin:/usr/sbin',
      onlyif  => "systemctl is-enabled ${unit} 2>/dev/null | grep -qx masked",
      before  => Service[$enabled_units],
    }
  }

  service { $enabled_units:
    ensure  => running,
    enable  => true,
    require => Package['unattended-upgrades'],
  }

  file { '/etc/apt/apt.conf.d/20auto-upgrades':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('profile/unattended_upgrades/20auto-upgrades.erb'),
    require => Package['unattended-upgrades'],
  }

  file { '/etc/apt/apt.conf.d/52unattended-upgrades-infrahouse':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('profile/unattended_upgrades/52unattended-upgrades-infrahouse.erb'),
    require => Package['unattended-upgrades'],
  }
}