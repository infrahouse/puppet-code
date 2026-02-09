# @summary: Create swap from a file
# Swap size is capped to avoid filling the root filesystem on instances
# with large RAM and small root volumes (e.g. c5.metal with 192 GB RAM
# and a 30 GB root volume).  The size is the minimum of:
#   - 2x total RAM (traditional rule, appropriate for small instances)
#   - 8 GB hard cap
#   - 25% of available disk space on /
class profile::swap () {
  $total_ram = $facts['memory']['system']['total_bytes']
  $eight_gb = 8 * 1024 * 1024 * 1024
  $disk_available = $facts['mountpoints']['/']['available_bytes']
  $disk_cap = $disk_available / 4
  $swap_size = min($total_ram * 2, $eight_gb, $disk_cap)
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
