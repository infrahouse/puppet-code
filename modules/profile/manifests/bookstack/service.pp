# @summary: Manages bookstack service.
class profile::bookstack::service (
) {

  service { 'postfix':
    ensure  => running,
    require => [
      Package['nginx-core'],
    ],
  }

}
