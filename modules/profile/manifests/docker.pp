# @summary: Installs docker repo, package and starts the service.
class profile::docker () {
  package { [
    'docker.io',
    'docker-compose',
    'docker-compose-v2',
    'docker-doc',
    'podman-docker',
    'containerd',
    'runc',
  ]:
    ensure => absent
  }

  stdlib::ensure_packages(['gnupg', 'curl', 'ca-certificates'])

  # Repo
  file { '/etc/apt/keyrings':
    ensure => directory,
    mode   => '0755',
  }

  file { '/etc/apt/keyrings/docker.gpg':
    source  => 'puppet:///modules/profile/docker.gpg',
    mode    => 'a+r',
    require => [
      File['/etc/apt/keyrings']
    ]
  }

  file { '/etc/apt/sources.list.d/docker.list':
    ensure  => file,
    content => template('profile/docker.list.erb'),
    notify  => Exec['profile::docker::apt_update'],
  }

  exec { 'profile::docker::apt_update':
    command     => ['apt-get', 'update'],
    path        => ['/usr/bin', '/usr/sbin',],
    refreshonly => true,
  }

  package { [
    'docker-ce',
    'docker-ce-cli',
    'containerd.io',
    'docker-buildx-plugin',
    'docker-compose-plugin',
  ]:
    ensure  => present,
    require => [
      File['/etc/apt/sources.list.d/docker.list'],
      Exec['profile::docker::apt_update'],
    ]
  }

  service {'docker':
    ensure  => running,
    require => [
      Package['docker-ce'],
      Package['docker-ce-cli'],
      Package['containerd.io'],
      Package['docker-buildx-plugin'],
      Package['docker-compose-plugin'],
    ]
  }

}
