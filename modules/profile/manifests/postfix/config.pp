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
  'profile::postfix::relayhost', undef, undef, []
),
  $mynetworks = lookup(
    'profile::postfix::mynetworks', undef, undef, []
  ),
) {
  $postfix_mydestination = ($mydestination + [$myhostname, $mydomain, 'localhost']).join(',')
  $postfix_relayhost = $relayhost.join(',')
  $postfix_mynetworks = ($mynetworks + ['127.0.0.0/8', '[::ffff:127.0.0.0]/104', '[::1]/128']).join(',')

  file { '/etc/postfix/main.cf':
    ensure  => file,
    content => template('profile/postfix/main.cf.erb'),
    notify  => Service['postfix'],
    require => [
      Package['postfix']
    ],
  }

}
