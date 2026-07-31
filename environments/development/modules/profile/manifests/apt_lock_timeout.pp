# @summary: Make apt-get wait for the dpkg lock instead of failing outright.
#
# Declared by profile::repos with `stage => init` so the drop-in exists before any
# Package resource in stage main. That ordering is the whole point: a drop-in
# applied halfway through the catalog does not help the Package resources Puppet
# already evaluated.
#
# Why this is needed at all: Ubuntu ships `binary::apt::DPkg::Lock::Timeout "120"`,
# and that scope applies ONLY to the `apt` command. Puppet's package provider,
# cloud-init and the AWS agents all shell out to `apt-get`, which inherits nothing
# and fails instantly on a held lock. Measured on noble/apt 2.8.3 against a held
# /var/lib/dpkg/lock-frontend: apt-get install exits 100 in 0s without the
# unscoped key, and 0 in 45s (waiting out a 40s lock) with it.
#
# Lock contention here is routine, not hypothetical:
#   - the Inspector and GuardDuty agents each dpkg-install ~1 min into every boot
#   - profile::unattended_upgrades deliberately unmasks and STARTS the apt-daily
#     timers mid-catalog, so an unattended-upgrade can begin during the run
#
# NOTE: the path is deliberately the same file infrahouse-ubuntu-pro writes from
# its provision.sh. Two drop-ins both setting this key would resolve by lexical
# filename order, which is a silent trap -- so Puppet converges the AMI's file
# rather than racing a second one of its own.
#
# @param timeout
#   Seconds apt-get waits for the dpkg lock. Sourced from the apt_lock_timeout
#   custom fact (set via the cloud-init module's custom_facts), defaulting to the
#   300 that current AMIs ship.
#
#   Keep it well inside the gha_runner bootstrap lifecycle hook (1200s,
#   default_result ABANDON): a genuinely wedged lock costs this many seconds per
#   Package resource, and the hook is not renewed during bootstrap.
class profile::apt_lock_timeout (
  Integer[1] $timeout = Integer(pick_default($facts['apt_lock_timeout'], 300)),
) {

  file { '/etc/apt/apt.conf.d/99-lock-timeout':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "DPkg::Lock::Timeout \"${timeout}\";\n",
  }
}
