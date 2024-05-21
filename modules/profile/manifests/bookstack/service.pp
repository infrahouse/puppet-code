# @summary: Manages bookstack service.
class profile::bookstack::service (
) {

  service { 'nginx':
    ensure  => running,
    require => [
      Package['nginx-core'],
      File['/etc/nginx/sites-available/default']
    ],
  }
}
