# @summary: Puppet role for an OpenVPN server
class role::openvpn_server () {

  include 'profile::base'
  include 'profile::openvpn_server'

  # Patch during provisioning so Inspector's first scan sees an already-patched
  # host. Takes the default fail_on_error => false: the VPN server is long-lived
  # and not disposable, so an unpatched-but-reachable server beats an ABANDONed
  # one.
  include 'profile::boot_security_upgrade'

  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}
