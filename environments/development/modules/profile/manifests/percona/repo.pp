# @summary: Installs Percona repository using percona-release package.
class profile::percona::repo () {
  $release_package_url = 'https://repo.percona.com/apt/percona-release_latest.generic_all.deb'
  $release_package_path = '/var/tmp/percona-release_latest.generic_all.deb'

  package { ['gnupg2', 'curl', 'lsb-release']:
    ensure => 'installed',
  }

  exec { 'download-percona-release':
    path    => '/usr/bin',
    command => "curl -o ${release_package_path} ${release_package_url}",
    creates => $release_package_path,
    require => Package['curl'],
  }

  exec { 'install-percona-release':
    path    => '/usr/bin:/usr/sbin:/sbin:/bin',
    command => "dpkg -i ${release_package_path}",
    unless  => 'dpkg -l percona-release',
    require => [
      Exec['download-percona-release'],
      Package['gnupg2'],
      Package['lsb-release'],
    ],
    notify  => Exec['percona-release-setup'],
  }

  exec { 'percona-release-setup':
    path        => '/usr/bin:/usr/sbin:/sbin:/bin',
    command     => 'percona-release setup ps80 -y',
    refreshonly => true,
    notify      => Exec['update-percona-repo'],
  }

  exec { 'update-percona-repo':
    path        => '/usr/bin',
    command     => 'apt-get update',
    refreshonly => true,
  }
}