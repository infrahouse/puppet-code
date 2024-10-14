# @summary: Configure bookstack.
class profile::bookstack::config (
  $bookstack_root,
  $www_user,
  $www_group,
) {
  $bookstack_app_key = aws_get_secret($facts['bookstack']['app_key_secret'], $facts['ec2_metadata']['placement'][
    'region'])
  $bookstack_app_url = $facts['bookstack']['app_url']
  $bookstack_db_host = $facts['bookstack']['db_host']
  $bookstack_db_database = $facts['bookstack']['db_database']
  $bookstack_db_username = $facts['bookstack']['db_username']
  $bookstack_db_password = aws_get_secret(
    $facts['bookstack']['db_password_secret'], $facts['ec2_metadata']['placement']['region']
  )['password']

  $bookstack_mail_from_name = $facts['bookstack']['mail_from_name']
  $bookstack_mail_from = $facts['bookstack']['mail_from']

  $bookstack_mail_host = $facts['bookstack']['mail_host']
  $bookstack_mail_port = $facts['bookstack']['mail_port']
  $bookstack_mail_username = $facts['bookstack']['mail_username']
  $bookstack_mail_password = aws_get_secret(
    $facts['bookstack']['mail_password_secret'],
    $facts['ec2_metadata']['placement']['region']
  )
  $bookstack_mail_encryption = $facts['bookstack']['mail_encryption']
  $bookstack_mail_verify_ssl = $facts['bookstack']['mail_verify_ssl']

  $bookstack_google_app_id = aws_get_secret(
    $facts['bookstack']['google_oauth_client_secret'], $facts['ec2_metadata']['placement']['region']
  )['web']['client_id']
  $bookstack_google_app_secret = aws_get_secret(
    $facts['bookstack']['google_oauth_client_secret'], $facts['ec2_metadata']['placement']['region']
  )['web']['client_secret']

  file { "${bookstack_root}/.env":
    ensure  => file,
    owner   => $www_user,
    group   => $www_group,
    mode    => '0600',
    content => template('profile/bookstack/env.erb'),
    require => [
      File[$bookstack_root]
    ],
  }

  file { '/etc/nginx/sites-available/default':
    ensure  => file,
    owner   => $www_user,
    group   => $www_group,
    mode    => '0644',
    content => template('profile/bookstack/nginx.erb'),
    require => [
      Package['nginx-core']
    ],
    notify  => Service['nginx']
  }
  file { '/etc/nginx/sites-enabled/default':
    ensure  => link,
    owner   => $www_user,
    group   => $www_group,
    mode    => '0644',
    target  => '/etc/nginx/sites-available/default',
    require => [
      File['/etc/nginx/sites-available/default'],
      Package['nginx-core']
    ],
    notify  => Service['nginx']
  }

  exec {'run_db_migration':
    path    => '/usr/bin',
    cwd     => $bookstack_root,
    command => 'php artisan migrate --force --no-interaction',
    user    => $www_user,
    unless  => 'php artisan migrate:status'
  }
}
