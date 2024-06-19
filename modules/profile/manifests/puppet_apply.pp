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
    'apply',
    $facts['ih-puppet'].get('manifest', '')
  ]

  $m = fqdn_rand(30)
  cron { 'puppet_apply':
    command     => $ih_cmd.join(' '),
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
