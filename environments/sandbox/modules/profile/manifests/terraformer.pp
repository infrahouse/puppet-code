# @summary: Terraformer profile.
class profile::terraformer (
  $terraform_version = lookup(
    'profile::terraformer::terraform_version', undef, undef, 'latest'
  )
) {
  package { 'terraform':
    ensure => $terraform_version
  }
}
