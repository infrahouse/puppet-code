# @summary: Create swap from a file
class profile::swap () {
  $total_ram = $facts['memory']['system']['total_bytes']
  $swap_size = $total_ram * 2
  $swap_file = '/swapfile'

  exec {'create_swap_file':
    command => "/usr/bin/fallocate -l ${swap_size} ${swap_file}",
    creates => $swap_file,
    notify  => Exec[swap_mkswap],
  }

  file { $swap_file:
    mode    => '0600',
    require => Exec['create_swap_file'],
  }

  exec {'swap_mkswap':
    command     => "/usr/sbin/mkswap ${swap_file}",
    refreshonly => true,
    notify      => Exec[swap_swapon],
    require     => File[$swap_file],
  }

  exec {'swap_swapon':
    command     => "/usr/sbin/swapon ${swap_file}",
    refreshonly => true,
  }

}
