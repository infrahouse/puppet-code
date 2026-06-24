# @summary: Shared, predictable Terraform provider plugin cache.
#
# Pins TF_PLUGIN_CACHE_DIR to a constant path so provider binaries are cached once
# under a deterministic prefix (instead of per-workdir .terraform/providers paths that
# vary run to run). This lets AWS Inspector EC2 scanning suppress the provider-binary
# noise with a single PREFIX filter while still scanning the host's OS packages.
#
# Terraform does not create the cache dir itself, so we create it here.
# See: https://developer.hashicorp.com/terraform/cli/config/config-file#provider-plugin-cache
class profile::terraformer::plugin_cache (
  String $cache_dir   = '/var/cache/terraform/plugins',
  String $cache_group = 'admin',
) {
  # ACL tooling so the admin group can share the cache (see exec below).
  stdlib::ensure_packages(['acl'])

  file { '/var/cache/terraform':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # setgid so new entries inherit the admin group; the default ACL below adds the
  # group-write that the umask would otherwise strip from nested dirs.
  file { $cache_dir:
    ensure  => directory,
    owner   => 'root',
    group   => $cache_group,
    mode    => '2775',
    require => File['/var/cache/terraform'],
  }

  # Default + access ACL so every provider dir/file terraform creates stays writable
  # by the admin group. Idempotent via the unless guard.
  exec { 'terraformer-plugin-cache-acl':
    command => "setfacl -R -m d:g:${cache_group}:rwx -m g:${cache_group}:rwx ${cache_dir}",
    path    => ['/usr/bin', '/bin'],
    unless  => "getfacl -pc ${cache_dir} | grep -qx 'default:group:${cache_group}:rwx'",
    require => [Package['acl'], File[$cache_dir]],
  }

  # Export the cache dir for interactive login shells; terraform reads this env var.
  file { '/etc/profile.d/terraform-plugin-cache.sh':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "# Managed by Puppet (profile::terraformer::plugin_cache)\nexport TF_PLUGIN_CACHE_DIR=${cache_dir}\n",
  }
}
