# @summary: Obtains an SSL certificate from https://letsencrypt.org/
class profile::letsencrypt () {
  require 'profile::infrahouse_toolkit'

  $hostname = $facts['networking']['hostname']
  $le_domain = $facts['letsencrypt']['domain']
  $le_email = $facts['letsencrypt']['email']
  $le_production = pick($facts['letsencrypt']['production'], false)
  $le_fqdn = "${hostname}.${le_domain}"

  if $le_production {
    $test_cert_arg = ''
  } else {
    $test_cert_arg = '--test-cert'
  }

  exec { 'obtain_certificate':
    path    => '/usr/local/bin',
    command => "ih-certbot certonly ${test_cert_arg} -d ${le_fqdn} --dns-route53 --agree-tos --email ${le_email}",
    creates => "/etc/letsencrypt/live/${le_fqdn}/privkey.pem",
  }

  cron { 'certbot_renew':
    command => '/usr/local/bin/ih-certbot --quiet renew',
    minute  =>  fqdn_rand(60),
    hour    =>  fqdn_rand(24),
    weekday => fqdn_rand(7),
  }
}
