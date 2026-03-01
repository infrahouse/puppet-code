# @summary Configures Percona Orchestrator with Raft clustering
class profile::percona::orchestrator::config () {
  $orchestrator_password = aws_get_secret(
    $facts['percona']['credentials_secret'], $facts['ec2_metadata']['placement']['region']
  )['orchestrator']
  $cluster_id = $facts['percona']['cluster_id']
  $private_ip = $facts['networking']['ip']

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

  file { '/etc/orchestrator.conf.json':
    ensure  => file,
    content => template('profile/percona/orchestrator.conf.json.erb'),
    notify  => Service['orchestrator'],
    require => Package['orchestrator'],
  }
}
