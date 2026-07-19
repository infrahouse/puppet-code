# @summary: Revokes OpenVPN certificates of deactivated Google Workspace users.
#
# A user who is suspended or deleted in Google Workspace can no longer mint a
# new certificate (the portal blocks their login), but any .ovpn they already
# downloaded keeps working until the CA revokes it. This class closes that gap
# by scheduling a daily reconciliation: valid CNs in the PKI index minus active
# Google users equals the set to revoke. Certificate CNs are Google email
# addresses, because the portal signs requests with EASYRSA_REQ_CN set to the
# authenticated user's email.
#
# The feature has three dependencies outside this repository, gated at the level
# each one can actually be observed:
#
#   1. terraform-aws-openvpn -- gated at COMPILE time on the
#      openvpn.google_directory_revocation fact, which Terraform sets from
#      enable_google_directory_revocation. Terraform knows this at provision
#      time, so nothing is installed at all on nodes where the feature is off.
#   2. infrahouse-toolkit, which must provide `ih-openvpn $sync_subcommand` --
#      gated at RUNTIME by the wrapper, since the toolkit ships on its own
#      release cycle and its version is not known when the catalog compiles.
#   3. Google Workspace, where the service account's client id must be
#      authorized for the directory scope -- also gated at RUNTIME, via the
#      wrapper's handling of the sync command's exit status. This step is a
#      human action in the Workspace admin console with no Terraform resource
#      behind it, so no fact can report it: enable_google_directory_revocation
#      can be true for days before anyone finishes the console step.
#
# Where the class is declared it only writes a file and a cron entry, so it can
# never fail a Puppet run, and the feature starts working on the next cron tick
# once dependencies 2 and 3 land -- no Puppet run, no Hiera change, no redeploy.
#
# There is no separate report-only mode or enforcement switch: enabling the
# feature in Terraform means it revokes.
#
# @param openvp_config_directory
#   OpenVPN configuration directory. Shared across the ASG over EFS, so it also
#   hosts the cluster-wide lock.
# @param wif_env_file
#   Workload Identity Federation environment file written by Terraform. Holds
#   no secret; the credential config it references is keyless and sources an
#   AWS identity from IMDS.
# @param sync_subcommand
#   The `ih-openvpn` subcommand implementing the sync. The wrapper probes for
#   it instead of pinning a toolkit version.
# @param ih_openvpn_path
#   The `ih-openvpn` executable. A bare name (the default) is resolved through
#   PATH, i.e. the packaged toolkit. Point it at a checkout's virtualenv to test
#   an unreleased subcommand against a real instance, e.g.
#   /home/ubuntu/code/infrahouse-toolkit/.venv/bin/ih-openvpn. The wrapper also
#   honours an $IH_OPENVPN environment variable, which overrides this for a
#   single ad-hoc run without a Puppet run.
# @param hour
#   Cron hour for the daily run.
# @param minute
#   Cron minute. Defaults to a per-node value derived from the hostname so the
#   ASG does not query the Directory API in lockstep.
# @param mailto
#   Where cron mails failures, including any unmet dependency.
class profile::openvpn_server::google_revocation_sync (
  String $openvp_config_directory,
  String $wif_env_file = lookup(
    'profile::openvpn_server::wif_env_file', undef, undef, '/opt/openvpn-wif/wif.env'
  ),
  String $sync_subcommand = lookup(
    'profile::openvpn_server::google_sync_subcommand', undef, undef, 'sync-google-users'
  ),
  String $ih_openvpn_path = lookup(
    'profile::openvpn_server::ih_openvpn_path', undef, undef, 'ih-openvpn'
  ),
  Integer $hour = lookup('profile::openvpn_server::google_sync_hour', undef, undef, 2),
  Integer $minute = lookup('profile::openvpn_server::google_sync_minute', undef, undef, fqdn_rand(60, 'openvpn-google-sync')),
  $mailto = lookup(
    'profile::cron::mailto', undef, undef, "root@${facts['networking']['hostname']}.${facts['networking']['domain']}"
  ),
) {

  $sync_script = "${openvp_config_directory}/google-user-sync.sh"

  # The lock lives on the EFS-backed config directory rather than /var/run so it
  # is shared by every instance in the ASG. They all mount the same PKI, and two
  # concurrent `easyrsa revoke` runs would race on index.txt.
  $lock_file = "${openvp_config_directory}/.google-user-sync.lock"

  file { $sync_script:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0700',
    content => template('profile/openvpn_server/google-user-sync.sh.erb'),
    require => Mount[$openvp_config_directory],
  }

  cron { 'openvpn_google_user_sync':
    command     => $sync_script,
    user        => 'root',
    hour        => $hour,
    minute      => $minute,
    environment => ["MAILTO=${mailto}"],
    require     => File[$sync_script],
  }
}