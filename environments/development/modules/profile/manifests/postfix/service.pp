# @summary: Manages Postfix service.
class profile::postfix::service (
) {

  service { 'postfix':
    ensure  => running,
    require => [
      Package['postfix'],
      File['/etc/postfix/main.cf'],
      File['/etc/mailname'],
    ],
  }

}
