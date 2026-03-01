# Plan: Implement Orchestrator Puppet Configuration Management (Issue #237)

## Context

Percona Orchestrator needs to be installed and configured alongside the existing Percona Server setup.
Orchestrator provides MySQL high-availability with automatic failover via Raft consensus.
This adds orchestrator support to the existing `profile::percona` module in the development environment.

## Design Decisions (from user input)

- **Raft node discovery**: `ih-ec2 list --cluster_id=<id> -c` queries the ASG at catalog compile time via Puppet's `generate()` function
- **Failover hooks**: Will reference `ih-*` toolkit commands (not Puppet-managed scripts)
- **Credentials**: Orchestrator password fetched via `aws_get_secret()` Puppet function
  (defined in `lib/puppet/functions/aws_get_secret.rb`). Secret name from
  `$facts['percona']['credentials_secret']`, password under the `orchestrator` key.
- **Package source**: `percona-orchestrator` from existing Percona APT repository (no new repo needed)

## Files to Create

### 1. `environments/development/modules/profile/manifests/percona/orchestrator.pp`

Top-level orchestrator class. Includes sub-classes:

```puppet
class profile::percona::orchestrator () {
  include profile::percona::orchestrator::install
  include profile::percona::orchestrator::config
  include profile::percona::orchestrator::service
}
```

### 2. `environments/development/modules/profile/manifests/percona/orchestrator/install.pp`

Installs the `percona-orchestrator` package from the Percona repo:

```puppet
class profile::percona::orchestrator::install () {
  package { 'percona-orchestrator':
    ensure  => 'installed',
    require => Class['profile::percona::repo'],
  }
}
```

### 3. `environments/development/modules/profile/manifests/percona/orchestrator/config.pp`

Uses `generate()` to call `ih-ec2 list` at catalog compile time to discover Raft peers:

```puppet
class profile::percona::orchestrator::config () {
  $orchestrator_password = aws_get_secret(
    $facts['percona']['credentials_secret'], $facts['ec2_metadata']['placement']['region']
  )['orchestrator']
  $cluster_id            = $facts['percona']['cluster_id']
  $private_ip            = $facts['networking']['ip']

  # Discover Raft nodes by querying the ASG at compile time
  $raft_nodes_raw = generate('/usr/local/bin/ih-ec2', 'list', "--cluster_id=${cluster_id}", '-c')
  $raft_nodes     = split(strip($raft_nodes_raw), ',')

  file { '/var/lib/orchestrator':
    ensure => directory,
    owner  => 'orchestrator',
    group  => 'orchestrator',
  }

  file { '/var/lib/orchestrator/raft':
    ensure  => directory,
    owner   => 'orchestrator',
    group   => 'orchestrator',
    require => File['/var/lib/orchestrator'],
  }

  file { '/etc/orchestrator.conf.json':
    ensure  => file,
    content => template('profile/percona/orchestrator.conf.json.erb'),
    notify  => Service['orchestrator'],
    require => Package['percona-orchestrator'],
  }
}
```

Note: `generate()` runs during catalog compilation (server-side). Since we use `puppet apply` (not a puppetserver), 
it runs locally on the node where `ih-ec2` is already installed via `profile::infrahouse_toolkit`.

### 4. `environments/development/modules/profile/templates/percona/orchestrator.conf.json.erb`

ERB template for `/etc/orchestrator.conf.json`:

```json
{
  "Debug": false,
  "ListenAddress": ":3000",
  "MySQLTopologyUser": "orchestrator",
  "MySQLTopologyPassword": "<%= @orchestrator_password %>",
  "RaftEnabled": true,
  "RaftDataDir": "/var/lib/orchestrator/raft",
  "RaftBind": "<%= @private_ip %>:10008",
  "RaftNodes": [
<% @raft_nodes.each_with_index do |node, i| -%>
    "<%= node %>:10008"<%= i < @raft_nodes.length - 1 ? ',' : '' %>
<% end -%>
  ],
  "SQLite3DataFile": "/var/lib/orchestrator/orchestrator.sqlite3",
  "PostFailoverProcesses": [
    "/usr/local/bin/ih-mysql failover-hook"
  ]
}
```

### 5. `environments/development/modules/profile/manifests/percona/orchestrator/service.pp`

```puppet
class profile::percona::orchestrator::service () {
  service { 'orchestrator':
    ensure  => running,
    enable  => true,
    require => [Package['percona-orchestrator'], File['/etc/orchestrator.conf.json']],
  }
}
```

## Files to Modify

### 6. `environments/development/modules/profile/manifests/percona.pp`

Add orchestrator include, gated by a fact so it's opt-in:

```puppet
if $facts.dig('percona', 'orchestrator') {
  include 'profile::percona::orchestrator'
}
```

Only enabled when Terraform sets the `percona.orchestrator` fact.

## Verification

1. **Lint**: `puppet-lint --fail-on-warnings environments/development/modules/profile`
2. **Review**: Class names match file paths, variables defined, relationships correct
3. **Pattern check**: ERB template uses `@variable` syntax, follows existing `mysqld.cnf.erb` patterns
