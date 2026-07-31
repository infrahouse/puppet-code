# @summary: Enable unattended-upgrades fleet-wide for automatic security updates.
#
# Included by profile::base so every host receives security fixes. This profile
# owns the unattended-upgrades configuration and asserts that the relevant units
# stay installed, enabled and running.
#
# The units ARE masked by the time this class runs, but the masking comes from
# cloud-init, not the AMI: terraform-aws-cloud-init's bootcmd runs
# `systemctl stop` + `systemctl mask` on apt-daily{,-upgrade}.{service,timer} and
# unattended-upgrades.service on every boot, before runcmd starts ih-puppet
# (terraform-aws-cloud-init#87 -- those timers race Puppet for the dpkg lock).
# The execs below undo it on every run, so the mask/unmask cycle repeats per boot.
#
# That masking predates vulnerability management and is obsolete policy. It is
# settled that unattended-upgrades IS wanted on these hosts and that Puppet is
# authoritative for it, so the unmask is deliberate, not a workaround. The
# cloud-init side will stop masking (terraform-aws-cloud-init#91); until it does,
# the execs below are what keeps unattended-upgrades running. Do not remove them
# before that lands -- and once it does, they become no-ops and can go.
#
# Meanwhile there is a small bounded patching gap: bootcmd masks on every boot,
# but runcmd/Puppet only runs at provisioning, so after a reboot of a long-lived
# instance the units stay masked until the next scheduled puppet apply -- at most
# ~30 min, since profile::puppet_apply runs at $m and $m+30.
#
# Hosts that must not be disrupted by an automatic service restart (e.g.
# Elasticsearch nodes) keep unattended-upgrades running but drop their own
# apt.conf.d blacklist entry (which appends to the list) and suppress automatic
# restarts separately (see profile::elastic::service).
class profile::unattended_upgrades (
  Boolean $automatic_reboot = lookup('profile::unattended_upgrades::automatic_reboot', undef, undef, false),
) {

  package { 'unattended-upgrades':
    ensure => present,
  }

  # Units that drive automatic upgrades:
  #   - the timers run the periodic download + upgrade
  #   - unattended-upgrades.service applies pending upgrades on shutdown/boot
  #
  # These arrive masked from cloud-init's bootcmd (see the class docstring), so
  # the execs below are load-bearing, not defensive. Without them
  # Service[$enabled_units] fails, because Puppet's service provider can neither
  # start nor enable a masked unit -- and a failed resource makes ih-puppet exit
  # 4 or 6 under --detailed-exitcodes, which trips ih-bootstrap's ERR trap and
  # ABANDONs the instance. The service provider cannot unmask either, hence execs.
  #
  # A masked apt-daily.service additionally prevents its own timer from starting
  # ("unit to trigger not loaded"), so the trigger .service units are listed here
  # too even though we never run them directly.
  #
  # Consequence worth knowing: unmasking and starting the timers here means the
  # timers are STARTED mid-catalog, so systemd evaluates their Persistent=true
  # backlog at that moment. That is what made infrahouse-ubuntu-pro's stale timer
  # stamps fire a catch-up unattended-upgrade during the Puppet run.
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