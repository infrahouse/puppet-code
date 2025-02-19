# @summary: Configure cron job for periodic puppet apply.
class profile::puppet_apply (
  $mailto = lookup(
    'profile::cron::mailto', undef, undef, "root@${facts['networking']['hostname']}.${facts['networking']['domain']}"
  ),
) {

  package { 'puppet-code':
    ensure => latest
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
