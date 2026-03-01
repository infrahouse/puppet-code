# @summary: Installs Percona repository using percona-release package.
class profile::percona::repo () {
  $release_package_url = 'https://repo.percona.com/apt/percona-release_latest.generic_all.deb'
  $release_package_path = '/var/tmp/percona-release_latest.generic_all.deb'

  $repo_name = $profile::percona::repo_name
  $percona_series = $profile::percona::percona_series

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
  }

  exec { 'percona-release-setup':
    path    => '/usr/bin:/usr/sbin:/sbin:/bin',
    command => "percona-release setup ${repo_name} -y",
    unless  => "test -f /etc/apt/sources.list.d/percona-${repo_name}-release.list",
    require => Exec['install-percona-release'],
    notify  => Exec['update-percona-repo'],
  }

  # XtraBackup 8.4 lives in its own repo (pxb-84-lts), not in ps-84-lts
  # XtraBackup 8.0 is included in ps80, so no extra repo needed
  if $percona_series == '8.4' {
    exec { 'enable-pxb-repo':
      path    => '/usr/bin:/usr/sbin:/sbin:/bin',
      command => 'percona-release enable pxb-84-lts',
      unless  => 'test -f /etc/apt/sources.list.d/percona-pxb-84-lts-release.list',
      require => Exec['install-percona-release'],
      notify  => Exec['update-percona-repo'],
    }
  }

  exec { 'update-percona-repo':
    path        => '/usr/bin',
    command     => 'apt-get update',
    refreshonly => true,
  }
}