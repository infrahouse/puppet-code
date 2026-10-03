# @summary: Converges the HashiCorp APT repository (source list + signing key).
#
# HashiCorp rotated its package signing key on 2026-09-09 (HCSEC-2026-33) with no
# notice, no overlap and no cross-signature, and every host holding a pinned copy
# of the old key failed `apt-get update`. A pinned key cannot survive that: the
# old key never vouches for the new one. So the keyring is re-fetched from
# https://apt.releases.hashicorp.com/gpg on every run and replaced when it
# differs. Trust is anchored on TLS to that URL -- the same trust HashiCorp's own
# install instructions ask for.
#
# Declared with `stage => init` by profile::terraformer, and ordered before
# Class['apt::update']. That ordering is the whole point: profile::repos runs
# apt_update in stage init on every run, and when it fails every resource in
# stage main is skipped -- including anything there that could fix the key.
#
# A failed fetch keeps the installed keyring (see converge-apt-keyring.sh), so an
# outage of HashiCorp's key URL does not fail the run by itself.
#
# The source list is the path cloud-init's `extra_repos` seed writes (from
# terraform-aws-terraformer 3.x and older), so Puppet rewrites that file rather
# than adding a second line for the same URL with a different signed-by -- apt
# rejects that with "Conflicting values set for option Signed-By". It is also
# the path HashiCorp's install instructions use. The keyring cloud-init seeded
# for that line is removed once the line no longer points at it.
#
# @param codename APT codename of the HashiCorp suite; derived from the node's OS
#   facts by default.
class profile::hashicorp_repo (
  String[1] $codename = $facts['os']['distro']['codename'],
) {
  $script      = '/usr/local/sbin/converge-apt-keyring.sh'
  $key_url     = 'https://apt.releases.hashicorp.com/gpg'
  $keyring     = '/etc/apt/keyrings/hashicorp.gpg'
  $source_list = '/etc/apt/sources.list.d/hashicorp.list'

  file { $script:
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/profile/converge-apt-keyring.sh',
  }

  # 'check' short-circuits when already in sync, so steady state is a no-op and
  # the exec (with its fingerprint output) only shows up in a run on a key change.
  exec { 'profile::hashicorp_repo::converge':
    command   => "${script} apply ${key_url} ${keyring}",
    unless    => "${script} check ${key_url} ${keyring}",
    path      => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    logoutput => true,
    require   => File[$script],
    before    => Class['apt::update'],
  }

  file { $source_list:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "deb [signed-by=${keyring}] https://apt.releases.hashicorp.com ${codename} main\n",
    require => Exec['profile::hashicorp_repo::converge'],
    before  => Class['apt::update'],
  }

  file { '/etc/apt/cloud-init.gpg.d/hashicorp.gpg':
    ensure  => absent,
    require => File[$source_list],
  }
}
