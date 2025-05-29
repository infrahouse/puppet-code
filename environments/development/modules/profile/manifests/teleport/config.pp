# @summary: Configure teleport.
class profile::teleport::config (
) {
  $hostname = $facts['networking']['hostname']
  $logfile = '/var/log/teleport/teleport.log'
  $public_addr = $facts['teleport']['public_addr']
  $storage_region = $facts['ec2_metadata']['placement']['region']
  $storage_table_name = $facts['teleport']['storage_table_name']
  $audit_bucket_name = $facts['teleport']['audit_bucket_name']
  $cluster_name = $facts['teleport']['cluster_name']
  $proxy_public_addr = $facts['teleport']['proxy_public_addr']

  file { '/var/log/teleport':
    ensure => directory,
  }

  file { '/etc/teleport.yaml':
    ensure  => file,
    mode    => '0644',
    content => template('profile/teleport/teleport.yaml.erb'),
    notify  => Service['teleport']
  }
}
