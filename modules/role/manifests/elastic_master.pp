# @summary: Puppet role for an elasticsearch node
class role::elastic_master () {

  include 'profile::base'
  include 'profile::elastic_master'

  # Patch during provisioning so Inspector's first findings describe an
  # already-patched host. Takes the default fail_on_error => false: a data-bearing
  # node that could not patch is still worth having.
  #
  # Safe alongside profile::elastic::service's suppression: that blacklists the
  # elasticsearch package and sets needrestart to list-only via apt.conf.d and
  # needrestart drop-ins, which unattended-upgrade honours no matter who invokes
  # it. (The blacklist is belt-and-braces here anyway -- elastic.co is not an
  # allowed origin, so unattended-upgrade would never upgrade Elasticsearch.)
  include 'profile::boot_security_upgrade'

  class { 'profile::postfix':
    postfix_inet_interfaces => '127.0.0.1',
  }
}

