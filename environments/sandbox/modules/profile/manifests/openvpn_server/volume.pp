# @summary: Configure OpenVPN Configuration volume.
class profile::openvpn_server::volume (
  $nfs_device,
  $mount_target = '/etc/openvpn',
  $user = 'root',
  $group = 'root',

) {
  file { $mount_target:
    ensure => 'directory',
    owner  => $user,
    group  => $group,
  }

  # Mount the NFS volume
  mount { $mount_target:
    ensure  => 'mounted',
    device  => $nfs_device,
    fstype  => 'nfs4',
    options => 'nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev',
    require => File[$mount_target],
  }

}
