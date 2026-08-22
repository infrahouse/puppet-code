# @summary: Puppet role for a terraformer instance
class role::terraformer () {

  include 'profile::base'
  include 'profile::terraformer'

  # Patch during provisioning so Inspector's first findings describe an
  # already-patched host. Takes the default fail_on_error => false: a failed
  # patch should not cost the instance.
  include 'profile::boot_security_upgrade'

  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
