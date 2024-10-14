# @summary: Changes kibana_system password.
class profile::elastic::kibana_user () {

  $kibana_system_secret = $facts['elasticsearch']['kibana_system_secret']
  $cmd = "ih-elastic passwd \
  --username kibana_system \
  --new-password-secret ${kibana_system_secret}"

  # Change kibana_system password unless it's already set.
  exec { 'kibana_system_passwd':
    path    => '/usr/local/bin',
    command => $cmd,
    unless  => 'ih-elastic --username kibana_system cluster-health',
    require => [
      Service['elasticsearch'],
      Package['infrahouse-toolkit'],
    ],
  }
}
