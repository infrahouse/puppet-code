# @summary: Configure cron job for periodic puppet apply.
class profile::puppet_apply (
  $mailto = lookup(
    'profile::cron::mailto', undef, undef, "root@${facts['networking']['hostname']}.${facts['networking']['domain']}"
  ),
) {

  package { 'puppet-code':
    ensure => latest
  }

  # puppet-agent arrives as an infrahouse-toolkit dependency, because ih-puppet
  # shells out to `puppet apply`. That package also enables the AGENT DAEMON,
  # which has no job on a masterless node: it wakes on its own runinterval, fails
  # to resolve the packaged default server `puppet`, logs "No more routes to ca"
  # and sleeps again -- on every host in the fleet, forever. Nothing in this
  # repository refers to it; the cron above is what actually applies the catalog.
  #
  # Masked rather than merely disabled, for two reasons. A puppet-agent upgrade
  # re-enables the unit from its own postinst, so `enable => false` would decay.
  # And the failure mode if that hostname ever DID resolve -- a DHCP search
  # domain, a host someone names `puppet` -- is not a noisy log: every node would
  # fetch and apply a catalog from whatever answered, in the agent's own default
  # environment `production`. A mask is the only state a package upgrade cannot
  # quietly undo.
  #
  # Package['puppet-agent'] is deliberately NOT declared alongside this. It
  # arrives as an infrahouse-toolkit dependency and is necessarily installed
  # before any catalog can be applied, so there is nothing to order against --
  # and adding a base-level Package for something a role might also declare
  # natively is how duplicate-declaration failures happen.
  service { 'puppet':
    ensure => stopped,
    enable => mask,
  }

  $ih_cmd = [
    'ih-puppet',
    $facts['ih-puppet']['debug'] ? {
      true  => '--debug',
      false => ''
    },
    '--quiet',
    '--environment',
    $facts['puppet_environment'],
    '--environmentpath',
    $facts['ih-puppet']['environmentpath'],
    '--root-directory',
    $facts['ih-puppet']['root-directory'],
    '--hiera-config',
    $facts['ih-puppet']['hiera-config'],
    '--module-path',
    $facts['ih-puppet']['module-path'],
    ('cancel_instance_refresh_on_error' in $facts['ih-puppet'] and $facts['ih-puppet']['cancel_instance_refresh_on_error']) ? {
      true  => '--cancel-instance-refresh-on-error',
      false => ''
    },
    'apply',
    $facts['ih-puppet'].get('manifest', '')
  ]

  $puppet_wrapper = $ih_cmd.join(' ')

  file { '/usr/local/bin/puppet-wrapper':
    content => template('profile/puppet-wrapper.erb'),
    mode    => '0755',
    owner   => 'root',
  }

  $puppet_lookup = [
    'puppet', 'lookup',
    '--environment', $facts['puppet_environment'],
    '--hiera_config', $facts['ih-puppet']['hiera-config'],
    '--render_as', 'json',
    '--merge', 'deep',
    '--facts', '/etc/puppetlabs/facter/facts.d/puppet.yaml'
  ].join(' ')
  file { '/usr/local/bin/puppet-lookup':
    content => template('profile/puppet-lookup.erb'),
    mode    => '0755',
    owner   => 'root',
  }

  $m = fqdn_rand(30)
  cron { 'puppet_apply':
    command     => '/usr/local/bin/puppet-wrapper',
    environment => [
      'PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin',
      "MAILTO=${mailto}"
    ],
    user        => 'root',
    minute      => [$m, $m + 30],
    require     => [
      Package['puppet-code'],
      Package['infrahouse-toolkit']
    ]
  }
}
