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
  $aws_account_id = $facts['teleport']['aws_account_id']
  $environment = $facts['puppet_environment']

  $discover_regions_array = $facts['teleport']['discover_regions']
  $discover_regions_string = $discover_regions_array.sort.map |$r| { "\"${r}\"" }.join(', ')

  file { '/var/log/teleport':
    ensure => directory,
  }

  file { '/etc/teleport.yaml':
    ensure  => file,
    mode    => '0644',
    content => template('profile/teleport/teleport.yaml.erb'),
    notify  => Service['teleport']
  }

  file { '/var/lib/teleport':
    ensure => directory,
  }

  file { '/var/lib/teleport/token.yaml':
    ensure  => file,
    mode    => '0644',
    content => template('profile/teleport/token.yaml.erb'),
    require => [
      File['/var/lib/teleport'],
    ],
  }

  exec { 'wait_for_teleport_port_3025':
    command => 'sh -c "while ! ss -tln | grep -q \":3025 \"; do sleep 1; done"',
    path    => ['/bin', '/usr/bin', '/usr/sbin'],
    timeout => 300,
    require => Service['teleport'],
    unless  => 'ss -tln | grep -q ":3025 "',
  }

  exec { 'create_invite_token':
    command => 'tctl create  -f /var/lib/teleport/token.yaml',
    path    => ['/usr/local/bin:/usr/bin'],
    require => [
      File['/var/lib/teleport/token.yaml'],
      Service['teleport'],
      Exec['wait_for_teleport_port_3025'],
    ],
    unless  => 'test "$(tctl get token/aws-discovery-iam-token --format=json | jq -r ".[0].kind")" = "token"',
  }

  $github_connector = {
    'version' => 'v3',
    'kind' => 'github',
    'metadata' => {
      'name' => 'github',
    },
    'spec' => {
      'api_endpoint_url' => 'https://api.github.com',
      'client_id'        => $facts['teleport']['github_client_id'],
      'client_secret'    => aws_get_secret(
        $facts['teleport']['github_client_secret_secret_name'],
        $facts['ec2_metadata']['placement']['region']
      ),
      'display'          => '',
      'redirect_url'     => 'https://teleport.infrahouse.com:443/v1/webapi/github/callback',
      'teams_to_roles'   => [
        {
          'organization' => 'infrahouse',
          'roles'        => ['access', 'editor'],
          'team'         => 'developers',
        }
      ]
    }
  }

  file { '/var/lib/teleport/github.yaml':
    ensure  => file,
    content => stdlib::to_yaml($github_connector),
    mode    => '0600',
    require => [
      File['/var/lib/teleport'],
    ],
    notify  => Exec['sync-connector-github'],
  }

  exec { 'sync-connector-github':
    command     => 'tctl create -f /var/lib/teleport/github.yaml',
    refreshonly => true,
    path        => ['/usr/local/bin:/usr/bin'],
    require     => [
      File['/var/lib/teleport/github.yaml'],
      Service['teleport'],
      Exec['wait_for_teleport_port_3025'],
    ],
  }

}
