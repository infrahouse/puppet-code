# @summary: Installs elasicsearch repository.
class profile::elastic::repo () {
  $public_key_file = '/var/tmp/GPG-KEY-elasticsearch'
  $sign_file = '/usr/share/keyrings/elasticsearch-keyring.gpg'
  file { $public_key_file:
    source => 'puppet:///modules/profile/elastic_master/GPG-KEY-elasticsearch',
    notify => Exec['update-elastic-sign-key']
  }

  exec { 'update-elastic-sign-key':
    path        => '/usr/bin',
    command     => "gpg --dearmor -o ${sign_file} ${public_key_file}",
    refreshonly => true,
    require     => [
      Package['gnupg2'],
      Package['ubuntu-keyring'],
    ]
  }

  file { '/etc/apt/sources.list.d/elastic-8.x.list':
    content => "deb [signed-by=${sign_file}] https://artifacts.elastic.co/packages/8.x/apt stable main",
    notify  => [
      Exec['update-elastic-repo'],
    ],
    require => [
      Exec['update-elastic-sign-key'],
    ]
  }

  exec { 'update-elastic-repo':
    path        => '/usr/bin',
    command     => 'apt-get update',
    refreshonly => true,
  }
}
