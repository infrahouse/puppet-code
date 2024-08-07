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
  $postfix_inet_interfaces = 'all',
  $whitelist_domains = lookup(
    'profile::postfix::whitelist_domains', undef, undef, []
  ),
) {
  $postfix_mydestination = ($mydestination + [$myhostname, $mydomain, $facts['networking']['fqdn'], 'localhost']).join(',')
  $postfix_relayhost = $relayhost
  $postfix_mynetworks = ($mynetworks + ['127.0.0.0/8', '[::ffff:127.0.0.0]/104', '[::1]/128']).join(',')
  $postfix_whitelist_domains = ($whitelist_domains + ['google.com'])

  $postfix_smtp_user = 'postfix' in $facts ? {
    true => aws_get_secret(
      $facts['postfix']['smtp_credentials'],
      $facts['ec2_metadata']['placement']['region']
    )['user'],
    false => 'Not configured'
  }
  $postfix_smtp_password = 'postfix' in $facts ? {
    true => aws_get_secret(
      $facts['postfix']['smtp_credentials'],
      $facts['ec2_metadata']['placement']['region']
    )['password'],
    false => 'See https://registry.terraform.io/modules/infrahouse/jumphost/aws/latest'
  }

  $smtp_sasl_auth_enable = 'postfix' in $facts ? {
    true => 'yes',
    false => 'no'
  }

  file { '/etc/mailname':
    ensure  => file,
    content => "${myhostname}.${mydomain}",
    owner   => 'root',
    mode    => '0644',
    notify  => Service['postfix'],
  }

  file { '/etc/postfix/main.cf':
    ensure  => file,
    content => template('profile/postfix/main.cf.erb'),
    owner   => 'root',
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

  file { '/etc/postfix/generic':
    content => "root root@${myhostname}.${mydomain}\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    notify  => Exec[refesh_postfix_generic],
    require => Package['postfix'],
  }

  exec { 'refesh_hostname':
    command     => "/usr/bin/hostname ${myhostname}.${mydomain}",
    refreshonly => true,
  }

  exec { 'refesh_postfix_generic':
    command => '/usr/sbin/postmap /etc/postfix/generic',
    require => [
      Package['postfix'],
      File['/etc/mailname'],
    ],
    notify  => Service[postfix],
    creates => '/etc/postfix/generic.db',
  }

  file { '/etc/postfix/rbl_override':
    content => template('profile/postfix/rbl_override.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    notify  => Exec[refesh_postfix_generic],
    require => Package['postfix'],
  }

  exec { 'refesh_rbl_override':
    command => '/usr/sbin/postmap /etc/postfix/rbl_override',
    require => [
      Package['postfix'],
      File['/etc/postfix/rbl_override'],
    ],
    notify  => Service[postfix],
    creates => '/etc/postfix/rbl_override.db',
  }

}
