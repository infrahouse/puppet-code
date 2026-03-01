# @summary: Installs Percona Server and related components
class profile::percona () {

  $server_version = pick_default($facts.dig('percona', 'server_version'), '')

  $percona_series = $server_version ? {
    ''        => '8.0',
    'latest'  => '8.4',
    /^8\.4\./ => '8.4',
    default   => '8.0',
  }

  $repo_name = $percona_series ? {
    '8.4'   => 'ps-84-lts',
    default => 'ps80',
  }

  # Normalize version to full apt format
  # Percona apt versions have a distro suffix, e.g. 8.4.7-7-1.noble
  # Accept both short (8.4.7-7) and full (8.4.7-7-1.noble) forms
  $codename = $facts['os']['distro']['codename']
  $server_ensure = $server_version ? {
    ''       => 'installed',
    'latest' => 'installed',
    default  => $server_version =~ /\.${codename}$/ ? {
      true    => $server_version,
      default => "${server_version}-1.${codename}",
    },
  }

  # XtraBackup package name differs between series
  $xtrabackup_package = $percona_series ? {
    '8.4'   => 'percona-xtrabackup-84',
    default => 'percona-xtrabackup-80',
  }

  include 'profile::percona::repo'
  include 'profile::percona::packages'
  include 'profile::percona::config'
  include 'profile::percona::service'
  include 'profile::percona::bootstrap'

}
