# @summary: Terraformer profile.
class profile::terraformer (
  $terraform_version = lookup(
    'profile::terraformer::terraform_version', undef, undef, 'latest'
  )
) {
  # In the init stage, ahead of apt_update: a stale HashiCorp key fails
  # apt_update, and that skips everything in stage main. See the class.
  class { 'profile::hashicorp_repo':
    stage => init,
  }

  package { 'terraform':
    ensure => $terraform_version
  }

  # Audit logging for terraform command tracking
  include profile::terraformer::auditd

  # CloudWatch agent for logging and metrics
  include profile::terraformer::cloudwatch_agent

  # Shared Terraform provider plugin cache at a predictable path
  include profile::terraformer::plugin_cache
}
