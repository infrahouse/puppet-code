# @summary: Changes kibana_system password.
class profile::elastic::kibana_user () {

  $elastic_secret = $facts['elasticsearch']['elastic_secret']
  $kibana_system_secret = $facts['elasticsearch']['kibana_system_secret']
  $cmd = "ih-elastic passwd \
  --admin-password-secret ${elastic_secret} \
  --username kibana_system \
  --new-password-secret ${kibana_system_secret}"

  # Change kibana_system password unless it's already set.
  exec { 'kibana_system_passwd':
    path    => '/usr/local/bin',
    command => $cmd,
    unless  => "ih-elastic cluster-health --username kibana_system --password-secret ${kibana_system_secret}",
    require => [
      Service['elasticsearch'],
      Package['infrahouse-toolkit'],
    ],
  }
}
