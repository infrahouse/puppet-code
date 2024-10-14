# @summary: Installs bookstack packages.
class profile::bookstack::packages (
  $bookstack_package_url,
  $bookstack_root,
  $www_user,
  $www_group,
) {

  package { [
    'composer',
    'nginx-core',
    'php',
    'php-cli',
    'php-curl',
    'php-gd',
    'php-fpm',
    'php-mbstring',
    'php-mysql',
    'php-xml',
  ]:
    ensure => present,
  }

  package { ['apache2', 'apache2-bin', 'apache2-data', 'apache2-utils']:
    ensure => purged,
  }

  $package_path = '/var/tmp/bookstack.tar.gz'

  file { $bookstack_root:
    ensure => directory,
    owner  => $www_user,
    group  => $www_group,
  }

  exec { 'download_package':
    path    => '/usr/bin',
    command => "curl -o ${package_path} -L ${bookstack_package_url}",
    creates => $package_path,
    notify  => Exec['extract_package']
  }

  exec { 'extract_package':
    path    => '/usr/bin',
    user    => $www_user,
    command => "tar xf ${package_path} -C ${bookstack_root} --strip-components=1",
    creates => "${bookstack_root}/public/index.php",
    require => File[$bookstack_root],
  }

  file {
    [
      "${bookstack_root}/storage",
      "${bookstack_root}/bootstrap/cache",
      "${bookstack_root}/vendor",
    ]:
    ensure => directory,
    owner  => $www_user,
    group  => $www_group,
  }

  exec { 'run_composer':
    path        => '/usr/bin',
    cwd         => $bookstack_root,
    user        => $www_user,
    environment => ["HOME=${bookstack_root}"],
    command     => 'composer install --no-dev',
    creates     => "${bookstack_root}/vendor/autoload.php",
    require     => [
      Exec['extract_package'],
      Package['composer'],
      File["${bookstack_root}/storage"],
      File["${bookstack_root}/bootstrap/cache"],
      File["${bookstack_root}/vendor"],
    ]
  }
}
