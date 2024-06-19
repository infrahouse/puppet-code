# @summary: Configures Postfix.
class profile::postfix::config (
  $myhostname = lookup(
    'profile::postfix::myhostname', undef, undef, $facts['networking']['hostname']
  ),
  $mydomain = lookup(
    'profile::postfix::mydomain', undef, undef, $facts['networking']['domain']
  ),
  $mydestination = lookup(
    'profile::postfix::mydestination', undef, undef, []
  ),
  $relayhost = lookup(
  'profile::postfix::relayhost', undef, undef,
    "[email-smtp.${facts['ec2_metadata']['placement']['region']}.amazonaws.com]:587"
),
  $mynetworks = lookup(
    'profile::postfix::mynetworks', undef, undef, []
  ),
  $postfix_inet_interfaces = 'all'
) {
  $postfix_mydestination = ($mydestination + [$myhostname, $mydomain, $facts['networking']['fqdn'], 'localhost']).join(',')
  $postfix_relayhost = $relayhost
  $postfix_mynetworks = ($mynetworks + ['127.0.0.0/8', '[::ffff:127.0.0.0]/104', '[::1]/128']).join(',')

  $postfix_smtp_user = aws_get_secret(
    $facts['postfix']['smtp_credentials'],
    $facts['ec2_metadata']['placement']['region']
  )['user']
  $postfix_smtp_password = aws_get_secret(
    $facts['postfix']['smtp_credentials'],
    $facts['ec2_metadata']['placement']['region']
  )['password']

  file { '/etc/postfix/main.cf':
    ensure  => file,
    content => template('profile/postfix/main.cf.erb'),
    owner   => 'postfix',
    mode    => '0600',
    notify  => Service['postfix'],
    require => [
      Package['postfix']
    ],
  }

  file { '/etc/hostname':
    ensure  => file,
    content => "${myhostname}.${mydomain}\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    notify  => Exec[refesh_hostname]
  }

  host { $myhostname:
    ensure       => present,
    ip           => $facts['networking']['ip'],
    host_aliases => [
      "${myhostname}.${mydomain}"
    ],
    target       => '/etc/hosts',
  }

  exec { 'refesh_hostname':
    command     => "/usr/bin/hostname ${myhostname}.${mydomain}",
    refreshonly => true,
  }
}
