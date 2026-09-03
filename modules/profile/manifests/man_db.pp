# @summary: Stop the man-db dpkg trigger from rebuilding the whole index on every
# package install.
#
# `mandb` does not reindex the pages a package just added -- it re-parses every
# page under /usr/share/man and rebuilds /var/cache/man from scratch. Measured on
# a sandbox actions-runner (t3a.xlarge, 5237 pages): 138.9s of user CPU for a run
# with nothing to do, and 0.13s for the very next run once that index landed. It
# is CPU-bound, so a bigger instance buys nothing.
#
# The cost is per dpkg TRANSACTION, not per package, and Puppet gives every
# Package resource its own transaction: on that host `zip` took 136s while
# `osv-scanner` took 1s -- the difference is whether the package drops a file in
# /usr/share/man, not how big it is. unattended-upgrade multiplies it again,
# because Unattended-Upgrade::MinimalSteps (default true) splits its work into
# many small transactions: 26 pending upgrades became four chunks of ~140s each,
# one of which was the single package `cpio`.
#
# On that instance ~1240s of a ~1600s provisioning window was man-db, which is
# what pushed actions-runner launches past the 1200s bootstrap lifecycle hook and
# turned routine scale-out into ABANDON churn. See infrahouse/puppet-code#300.
#
# WHY A FILE AND NOT JUST DEBCONF
# The obvious fix -- `debconf-set-selections` on man-db/auto-update -- does NOT
# work on its own. man-db's postinst reads debconf only on *configure*, and caches
# the answer as /var/lib/man-db/auto-update; the TRIGGER path checks that file and
# nothing else:
#
#   run_mandb () {
#       if [ ! -e /var/lib/man-db/auto-update ]; then
#           echo "Not building database; man-db/auto-update is not 'true'." >&2
#           return 0
#
# Verified in a noble container: with the debconf answer set to false but the
# marker still present, an install still ran mandb; with the marker removed, the
# trigger fired and returned immediately. So the file is the load-bearing half.
# The debconf answer is still set, because it is what keeps the marker from coming
# back the next time man-db itself is upgraded -- which unattended-upgrade can do
# in the middle of a provisioning run, precisely where the tax hurts most.
#
# Declared with `stage => init` by profile::base. That ordering is the whole
# point: a marker removed halfway through the catalog does not help the Package
# resources Puppet already evaluated.
#
# NOT COVERED: cloud-init installs its own package set before Puppet exists on the
# box, and pays one full rebuild there (~138s of the run measured above). Only a
# dpkg path-exclude baked into the AMI can reach that transaction.
#
# @param auto_update
#   Whether man-db may rebuild its index on package installs. false (default)
#   fleet-wide: these hosts are disposable and nobody reads man pages on them.
#   Setting it true restores stock Ubuntu behaviour for a role that wants a
#   working `man -k` more than it wants the provisioning time back.
class profile::man_db (
  Boolean $auto_update = lookup('profile::man_db::auto_update', undef, undef, false),
) {

  # What man-db's postinst caches the debconf answer into, and the only thing its
  # trigger path consults.
  $marker = '/var/lib/man-db/auto-update'

  $selection = $auto_update ? {
    true    => 'true',
    default => 'false',
  }

  $marker_ensure = $auto_update ? {
    true    => file,
    default => absent,
  }

  file { $marker:
    ensure => $marker_ensure,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
  }

  # debconf-set-selections, debconf-show and debconf-communicate all ship in the
  # `debconf` package, which is essential on Ubuntu -- nothing to install first.
  exec { 'man-db-auto-update-selection':
    command => "echo 'man-db man-db/auto-update boolean ${selection}' | debconf-set-selections",
    unless  => "debconf-show man-db | grep -q 'man-db/auto-update: ${selection}'",
    path    => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
  }
}
