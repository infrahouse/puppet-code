# @summary: Configures Percona Server my.cnf with GTID replication settings.
class profile::percona::config () {

  # Generate unique server-id from IP address last two octets
  $ip_parts = split($facts['networking']['ip'], '[.]')
  $server_id = Integer($ip_parts[2]) * 256 + Integer($ip_parts[3])

  # Auto-calculate buffer pool size (75% of RAM)
  $total_memory_mb = $facts['memory']['system']['total_bytes'] / 1024 / 1024
  $auto_buffer_pool = "${Integer($total_memory_mb * 0.75)}M"

  # Key paths - can be used by other profiles (e.g., cloudwatch)
  $log_error = pick(
    $facts.dig('percona', 'log_error'),
    lookup('profile::percona::log_error', undef, undef, undef),
    '/var/log/mysql/error.log'
  )

  # Default MySQL configuration
  $default_config = {
    'datadir'                        => '/var/lib/mysql',
    'innodb_buffer_pool_size'        => $auto_buffer_pool,
    'innodb_flush_log_at_trx_commit' => '1',
    'innodb_log_file_size'           => '256M',
    'log-error'                      => $log_error,
    'max_connections'                => '500',
    'pid-file'                       => '/var/run/mysqld/mysqld.pid',
    'socket'                         => '/var/run/mysqld/mysqld.sock',
    'sync_binlog'                    => '1',
  }

  # Get config from Hiera and facts
  $hiera_config = lookup('profile::percona::mysql_config', Hash, 'hash', {})
  $facts_config = pick($facts.dig('percona', 'mysql_config'), {})

  # Merge: defaults ← hiera ← facts (facts have highest priority)
  $mysql_config = $default_config + $hiera_config + $facts_config

  # Ensure config directory exists before package install
  file { '/etc/mysql':
    ensure => directory,
  }

  file { '/etc/mysql/mysql.conf.d':
    ensure  => directory,
    require => File['/etc/mysql'],
  }

  # Config must be in place BEFORE package installs so MySQL starts with correct settings
  # NOTE: No notify - config changes require manual/controlled restart
  # Do NOT auto-restart a master with active connections
  file { '/etc/mysql/mysql.conf.d/mysqld.cnf':
    ensure  => file,
    content => template('profile/percona/mysqld.cnf.erb'),
    require => File['/etc/mysql/mysql.conf.d'],
  }

}