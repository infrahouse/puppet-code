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
    ensure  => $elasticsearch_version,
    require => [
      File['/etc/apt/sources.list.d/elastic-8.x.list'],
      Exec['update-elastic-repo'],
    ],
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
