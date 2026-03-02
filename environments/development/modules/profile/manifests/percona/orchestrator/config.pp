# @summary Configures Percona Orchestrator with Raft clustering
class profile::percona::orchestrator::config () {
  $orchestrator_password = aws_get_secret(
    $facts['percona']['credentials_secret'], $facts['ec2_metadata']['placement']['region']
  )['orchestrator']
  $cluster_id         = $facts['percona']['cluster_id']
  $dynamodb_table     = $facts['percona']['dynamodb_table']
  $credentials_secret = $facts['percona']['credentials_secret']
  $vpc_cidr           = $facts['percona']['vpc_cidr']
  $read_tg_arn        = $facts['percona']['read_tg_arn']
  $write_tg_arn       = $facts['percona']['write_tg_arn']
  $private_ip         = $facts['networking']['ip']

  # Discover Raft nodes by querying the ASG at compile time
  $raft_nodes_raw = generate('/usr/local/bin/ih-ec2', 'list', "--cluster_id=${cluster_id}", '-c')
  $raft_nodes     = split(strip($raft_nodes_raw), ',').filter |$node| { $node != '' }

  file { '/var/lib/orchestrator':
    ensure => directory,
  }

  file { '/var/lib/orchestrator/raft':
    ensure  => directory,
    require => File['/var/lib/orchestrator'],
  }

  $networking_hostname = $facts['networking']['hostname']

  file { '/etc/profile.d/orchestrator.sh':
    ensure  => file,
    content => template('profile/percona/orchestrator-profile.sh.erb'),
  }

  file { '/etc/orchestrator.conf.json':
    ensure  => file,
    mode    => '0600',
    content => template('profile/percona/orchestrator.conf.json.erb'),
    notify  => Service['orchestrator'],
    require => Package['orchestrator'],
  }
}
