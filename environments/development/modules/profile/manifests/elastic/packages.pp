# @summary: Installs elasicsearch packages.
class profile::elastic::packages (
  String $elasticsearch_version = lookup(
    'profile::elastic::packages::elasticsearch_version',
    undef,
    undef,
    'present'
  ),
) {

  package { 'elasticsearch':
    ensure => $elasticsearch_version,
  }
  package { 'openssl':
    ensure => present,
  }

  exec { 'install-discovery-ec2':
    command => '/usr/share/elasticsearch/bin/elasticsearch-plugin install --batch discovery-ec2',
    creates => '/usr/share/elasticsearch/plugins/discovery-ec2',
    notify  => Service['elasticsearch'],
    require => [
      Package['elasticsearch'],
    ],
  }
}
