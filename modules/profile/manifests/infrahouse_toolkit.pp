class profile::infrahouse_toolkit () {
  package { 'infrahouse-toolkit':
    ensure => latest
  }
  package {
    [ 'reprepro', 's3fs', 'gpg' ]:
      ensure => present,
  }
}
