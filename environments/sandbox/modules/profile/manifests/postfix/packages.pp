# @summary: Postfix profile.
class profile::postfix::packages (
  $postfix_version = lookup(
    'profile::postfix::packages::postfix_version', undef, undef, 'latest'
  )

) {
  package { 'postfix':
    ensure => $postfix_version,
  }

  package { ['mailutils', 'mutt']:
    ensure => present,
  }
}
