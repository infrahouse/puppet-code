# @summary: OpenVPN server profile.
class profile::openvpn_server (
) {
  include 'profile::openvpn_server::packages'
}
