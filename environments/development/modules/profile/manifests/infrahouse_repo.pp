# @summary: Converges the InfraHouse APT repository (source list + signing key).
#
# cloud-init seeds both `/etc/apt/sources.list.d/50-infrahouse.list` and
# `/etc/apt/keyrings/infrahouse.gpg` at **first boot only** — it must, because the
# InfraHouse toolkit (ih-secrets) has to be installable before Puppet ever runs.
# This class **converges** both on every Puppet run so long-lived instances pick
# up a rotated signing key (the urgent case: the key expires) or a changed repo
# line without being reprovisioned.
#
# Ownership is intentionally shared: cloud-init writes the seed, Puppet keeps it
# in sync. The rendered source line is kept byte-identical to cloud-init's seed so
# the two never fight. Trust is anchored on the TLS channel to
# release-<codename>.infrahouse.com (no fingerprint pinning), consistent with
# cloud-init. On a fetch failure the previously installed keyring is left intact.
#
# @param codename APT codename whose repo/bundle to converge; derived from the
#   node's OS facts by default.
class profile::infrahouse_repo (
  String[1] $codename = $facts['os']['distro']['codename'],
) {
  $script      = '/usr/local/sbin/converge-infrahouse-keyring.sh'
  $keyring     = '/etc/apt/keyrings/infrahouse.gpg'
  $source_list = '/etc/apt/sources.list.d/50-infrahouse.list'

  stdlib::ensure_packages(['curl', 'gnupg', 'ca-certificates'])

  file { $script:
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/profile/converge-infrahouse-keyring.sh',
  }

  # Converge the keyring: 'check' short-circuits when already in sync, so steady
  # state is a no-op and the shared 'apt-get update' only fires on a key change.
  exec { 'profile::infrahouse_repo::converge':
    command => "${script} apply ${codename}",
    unless  => "${script} check ${codename}",
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    require => [
      File[$script],
      Package['curl'],
      Package['gnupg'],
    ],
    notify  => Exec['profile::infrahouse_repo::apt_update'],
  }

  # Converge the repo line. Kept byte-identical to cloud-init's first-boot seed;
  # $codename fills both the host (release-<codename>) and the suite.
  file { $source_list:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "deb [signed-by=${keyring}] https://release-${codename}.infrahouse.com/ ${codename} main\n",
    require => Exec['profile::infrahouse_repo::converge'],
    notify  => Exec['profile::infrahouse_repo::apt_update'],
  }

  # Single refresh point for both the keyring and the source list.
  exec { 'profile::infrahouse_repo::apt_update':
    command     => 'apt-get update',
    path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    refreshonly => true,
  }
}