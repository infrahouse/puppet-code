# @summary: Puppet role for a jumphost
class role::jumphost () {

  include 'profile::base'
  include 'profile::jumphost'

  # Patch during provisioning so Inspector's first scan sees an already-patched
  # host. Takes the default fail_on_error => false: unlike a runner, a jumphost
  # is long-lived and not disposable, so an unpatched-but-reachable bastion beats
  # an ABANDONed one.
  include 'profile::boot_security_upgrade'

  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
