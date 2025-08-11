# @summary: Manages teleport service.
class profile::teleport::service (
) {

  service { 'teleport':
    ensure  => running,
    require => [
      Package['teleport'],
      File['/etc/teleport.yaml'],
    ],
  }
}
