# @summary: Auditd configuration for OpenVPN server.
#
# Includes the base auditd profile for SOC2/ISO27001 compliance logging.
#
class profile::openvpn_server::auditd {

  include 'profile::auditd'

}
