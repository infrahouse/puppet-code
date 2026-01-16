# @summary: Terraformer profile.
class profile::terraformer (
  $terraform_version = lookup(
    'profile::terraformer::terraform_version', undef, undef, 'latest'
  )
) {
  package { 'terraform':
    ensure => $terraform_version
  }

  # Audit logging for terraform command tracking
  include profile::terraformer::auditd

  # CloudWatch agent for logging and metrics
  include profile::terraformer::cloudwatch_agent
}
