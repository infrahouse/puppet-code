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
