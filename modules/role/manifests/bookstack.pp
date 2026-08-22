# @summary: Puppet role for a BookStack wiki
class role::bookstack () {

  include 'profile::bookstack'

  # Patch during provisioning so Inspector's first findings describe an
  # already-patched host. Takes the default fail_on_error => false: the wiki is a
  # long-lived stateful singleton, so an unpatched-but-serving host beats an
  # ABANDONed one.
  #
  # This is the prerequisite half. Nothing tags BookStack instances yet -- the tag
  # comes from website-pod's defer_inspector_findings_until_patched, which must not
  # be enabled until this is deployed, or the tag would never be removed.
  include 'profile::boot_security_upgrade'

  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }

}
