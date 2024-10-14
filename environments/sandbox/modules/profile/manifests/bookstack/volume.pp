# @summary: Configure uploads volume.
class profile::bookstack::volume (
  $bookstack_root,
  $nfs_device,
  $mount_target,
  $www_user,
  $www_group,

) {
  file { $mount_target:
    ensure => 'directory',
    owner  => $www_user,
    group  => $www_group,
  }

  # Mount the NFS volume
  mount { $mount_target:
    ensure  => 'mounted',
    device  => $nfs_device,
    fstype  => 'nfs4',
    options => 'nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev',
    require => File[$mount_target],
  }

  file { "${mount_target}/.htaccess":
    ensure  => present,
    content => 'Options -Indexes',
    require => Mount[$mount_target]
  }
}
