# @summary: Configure echo service.
class profile::echo () {

  package { 'xinetd':
    ensure => present
  }

  file { '/etc/xinetd.d/echo':
    source  => 'puppet:///modules/profile/echo',
    mode    => '0644',
    notify  => Service[xinetd],
    require => [
      Package['xinetd']
    ],
  }

  service { 'xinetd':
    ensure  => running,
    require => [
      Package[xinetd],
      Cron['puppet_apply'],
    ]
  }
}
