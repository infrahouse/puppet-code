# @summary: Patch pending security updates once per boot, before Inspector scans.
#
# The symptom this exists for is fleet-wide, not runner-specific: a fresh
# instance comes up unpatched, unattended-upgrades is on a timer, and AWS
# Inspector scans the gap and opens a finding. The finding closes on the next
# unattended-upgrades run, but it has already REOPENED its vulnerability group by
# then -- and a group old enough to be reopened that way breaks the remediation
# SLA. Patching during provisioning closes the gap at the source.
#
# Instances are expected to launch tagged InspectorEc2Exclusion so Inspector
# leaves them alone until the script drops that tag. Dropping it is BEST EFFORT:
# it needs ec2:DeleteTags on the instance profile and the launch-time tag from
# Terraform, neither of which is in place fleet-wide yet. A host with neither is
# no worse off than before -- it just keeps being scanned on Inspector's own
# schedule. See the script header for the full rationale.
#
# This profile is opt-in per role, NOT included by profile::base, so adding it to
# a role is a deliberate decision about that role's provisioning time.
#
# Declare it with `include` and set values in hiera per role. profile::github_runner
# is the exception: it declares this class resource-like because its values are
# derived from the runner's ASG lifecycle rather than site policy, and a
# resource-like declaration wins over hiera. Two roles cannot collide over that,
# since a node only ever has one role.
#
# @param budget
#   Seconds the script may spend in total on `apt-get update` +
#   `unattended-upgrade`, retries included. The bound is cumulative, not
#   per-attempt -- see the script header for why that distinction is
#   load-bearing. Keep it well inside the role's bootstrap lifecycle hook, since
#   nothing renews the hook during provisioning.
#
# @param fail_on_error
#   What a failed upgrade does to the Puppet run. false (default) logs and
#   continues: an unpatched-but-running host beats an ABANDONed one on anything
#   stateful. true fails the resource, which under ih-bootstrap ABANDONs the
#   instance -- correct only where instances are disposable and the ASG will just
#   launch another.
#
# @param exclusion_tag
#   EC2 tag key the script removes once it is done. Removal failures never fail
#   the run regardless of this value.
#
#   An EMPTY STRING is the off switch, not undef: Puppet resolves an explicitly
#   passed undef back to the parameter's default, so `exclusion_tag => undef`
#   would silently keep removing InspectorEc2Exclusion instead of disabling tag
#   handling.
class profile::boot_security_upgrade (
  Integer[1] $budget = lookup(
    'profile::boot_security_upgrade::budget', undef, undef, 480
  ),
  Boolean $fail_on_error = lookup(
    'profile::boot_security_upgrade::fail_on_error', undef, undef, false
  ),
  String $exclusion_tag = lookup(
    'profile::boot_security_upgrade::exclusion_tag', undef, undef, 'InspectorEc2Exclusion'
  ),
) {

  # unattended-upgrades has to be installed and configured before the script
  # shells out to `unattended-upgrade`. profile::base includes this too; include
  # is idempotent, and declaring it here keeps the dependency real rather than
  # assumed.
  include 'profile::unattended_upgrades'

  # The tag drop shells out to ec2metadata and aws. Both are preinstalled on the
  # Ubuntu cloud images, but declaring them beats probing at runtime -- it lets
  # the exec order itself after them. Without that edge a first provisioning run
  # can evaluate the exec before the packages, and the tag drop would silently
  # no-op on exactly the boot it matters most.
  #
  # awscli lives in profile::packages rather than here; including that class
  # makes the require below a real dependency instead of an assumption about
  # what else the catalog happens to contain.
  include 'profile::packages'

  package { 'cloud-guest-utils':
    ensure => present,
  }

  $script = '/usr/local/bin/boot-security-upgrade.sh'

  # tmpfs, so it clears on a real boot: the exec runs once per boot rather than
  # on every Puppet apply. Note a hibernation resume is NOT a boot, so a warm
  # pool instance keeps the marker across the warm->hot transition.
  $marker = '/run/boot-security-upgrade.done'

  $tag_option = empty($exclusion_tag) ? {
    true    => '--no-exclusion-tag',
    default => "--exclusion-tag ${exclusion_tag}",
  }

  # The script exits 1 when it gives up. Accepting that status is what "log and
  # continue" means; logoutput => true is what makes the "log" half true, since
  # the default on_failure would print nothing for a status we just declared a
  # success.
  $accepted_returns = $fail_on_error ? {
    true    => [0],
    default => [0, 1],
  }

  file { $script:
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/profile/boot_security_upgrade/boot-security-upgrade.sh',
  }

  exec { 'boot-security-upgrade':
    command   => "${script} --budget ${budget} --marker ${marker} ${tag_option}",
    path      => '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin',
    creates   => $marker,
    # Slightly above the script's own budget so the script always gets to exit and
    # log why it gave up, rather than being killed mid-report by Puppet. Puppet's
    # timeout fails the resource regardless of `returns`, so this is a backstop
    # for a wedged script, not part of the normal give-up path -- the script caps
    # every command it runs at the remaining budget to stay inside it.
    timeout   => $budget + 60,
    returns   => $accepted_returns,
    logoutput => true,
    require   => [
      Class['profile::unattended_upgrades'],
      File[$script],
      Package['awscli'],
      Package['cloud-guest-utils'],
    ],
  }

}
