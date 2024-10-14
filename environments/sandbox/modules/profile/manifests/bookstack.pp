# @summary: Installs bookstack applicartion
class profile::bookstack (
  $bookstack_package_url = lookup(
    'profile::bookstack::bookstack_package_url',
    undef,
    undef,
    'https://github.com/BookStackApp/BookStack/archive/refs/tags/v24.05.tar.gz'
  )
)
{
  include 'profile::base'

  $bookstack_root = '/var/www/bookstack'
  $www_user = 'www-data'
  $www_group = 'www-data'

  class { 'profile::bookstack::packages':
    bookstack_package_url => $bookstack_package_url,
    bookstack_root        => $bookstack_root,
    www_user              => $www_user,
    www_group             => $www_group,
  }

  $dns_name = $facts['efs']['dns_name']
  $nfs_device = "${dns_name}:/"
  class { 'profile::bookstack::volume':
    bookstack_root => $bookstack_root,
    nfs_device     => $nfs_device,
    mount_target   => "${bookstack_root}/public/uploads",
    www_user       => $www_user,
    www_group      => $www_group,
  }

  class { 'profile::bookstack::config':
    bookstack_root => $bookstack_root,
    www_user       => $www_user,
    www_group      => $www_group,
  }

  include 'profile::bookstack::service'
}
