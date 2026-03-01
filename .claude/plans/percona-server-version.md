# Percona Server Version Control via Puppet Facts

**Status: Terraform side done. Puppet implementation pending.**

## Goal

Support installing a specific Percona Server version (8.0.x or 8.4.x) controlled
by a Terraform variable, passed as the custom fact `$facts['percona']['server_version']`.

This enables safe rolling upgrades via ASG instance refresh instead of
uncontrolled Puppet-driven package updates.

## Fact Values

Terraform passes `$facts['percona']['server_version']` with one of:

| Fact value             | Meaning                | Repo command                         |
|------------------------|------------------------|--------------------------------------|
| `""` (empty)           | Latest 8.0 (default)   | `percona-release setup ps80 -y`      |
| `"latest"`             | Latest 8.4             | `percona-release setup ps-84-lts -y` |
| `"8.0.45-36"`          | Pinned 8.0 (short)     | `percona-release setup ps80 -y`      |
| `"8.4.7-7"`            | Pinned 8.4 (short)     | `percona-release setup ps-84-lts -y` |
| `"8.0.45-36-1.noble"`  | Pinned 8.0 (full apt)  | `percona-release setup ps80 -y`      |
| `"8.4.7-7-1.noble"`    | Pinned 8.4 (full apt)  | `percona-release setup ps-84-lts -y` |

## Version String: Short Form → Full Apt Version

Percona's release notes show versions like `8.0.45-36` and `8.4.7-7`, but apt
requires the full string `8.0.45-36-1.noble` or `8.4.7-7-1.noble`.

The suffix is always `-1.{codename}` — the Debian package revision (`-1`) plus
the Ubuntu codename. Percona has never published a `-2` revision.

**Puppet must accept both forms.** If the version doesn't already end with the
codename suffix, append `-1.{codename}` automatically:

```puppet
# Normalize version to full apt format
$codename = $facts['os']['distro']['codename']
$apt_version = $server_version ? {
  ''       => 'installed',
  'latest' => 'installed',
  default  => $server_version =~ /\.${codename}$/ ? {
    true    => $server_version,
    default => "${server_version}-1.${codename}",
  },
}
```

This way the user can copy-paste `8.4.7-7` from Percona's website and it works.

## Files to Change

### 1. `profile::percona::repo` (`manifests/percona/repo.pp`)

**Current**: hardcoded `percona-release setup ps80 -y`

**Change**: derive the repo setup command from the fact.

```puppet
$server_version = pick($facts.dig('percona', 'server_version'), '')

$percona_series = $server_version ? {
  ''          => '8.0',
  'latest'    => '8.4',
  /^8\.4\./   => '8.4',
  default     => '8.0',
}

$repo_name = $percona_series ? {
  '8.4'   => 'ps-84-lts',
  default => 'ps80',
}

exec { 'percona-release-setup':
  path        => '/usr/bin:/usr/sbin:/sbin:/bin',
  command     => "percona-release setup ${repo_name} -y",
  refreshonly => true,
  notify      => Exec['update-percona-repo'],
}
```

### 2. `profile::percona::packages` (`manifests/percona/packages.pp`)

**Current**: all three packages use `ensure => 'installed'` with hardcoded names.

**Change**: derive `ensure` and package names from the fact. Normalize the
version string to the full apt format when pinning.

```puppet
$server_version = pick($facts.dig('percona', 'server_version'), '')
$codename = $facts['os']['distro']['codename']

$percona_series = $server_version ? {
  ''          => '8.0',
  'latest'    => '8.4',
  /^8\.4\./   => '8.4',
  default     => '8.0',
}

# Normalize version: append -1.{codename} if not already present
$server_ensure = $server_version ? {
  ''       => 'installed',
  'latest' => 'installed',
  default  => $server_version =~ /\.${codename}$/ ? {
    true    => $server_version,
    default => "${server_version}-1.${codename}",
  },
}

# XtraBackup package name differs between series
$xtrabackup_package = $percona_series ? {
  '8.4'   => 'percona-xtrabackup-84',
  default => 'percona-xtrabackup-80',
}

package { 'percona-server-server':
  ensure  => $server_ensure,
  require => [
    Class['profile::percona::repo'],
    Class['profile::percona::config'],
  ],
}

package { 'percona-server-client':
  ensure  => $server_ensure,
  require => Class['profile::percona::repo'],
}

package { $xtrabackup_package:
  ensure  => 'installed',
  require => Class['profile::percona::repo'],
}
```

Note: XtraBackup uses `'installed'` (not pinned) because its version doesn't
track the server version string.

### 3. `profile::percona::config` — template (`templates/percona/mysqld.cnf.erb`)

**Current**: comment says "Percona Server 8.0 configuration".

**Change**: minor — update comment or make it dynamic. The actual config
directives are compatible between 8.0 and 8.4 (GTID, binlog, replication).

Note: 8.4 deprecated `binlog_format` (ROW is the only option) and
`log_slave_updates` (always ON). These settings are harmless but will produce
deprecation warnings in the MySQL error log on 8.4. Consider conditionally
omitting them for 8.4 via the `$percona_series` variable, or just accept the
warnings for now.

## DRY: Shared Series Logic

The series derivation (`$server_version` → `$percona_series`) is needed in
both `repo.pp` and `packages.pp`. Options:

1. **Duplicate it** — simple, two files, minimal coupling
2. **Extract to a shared variable in `profile::percona`** — pass as class param
3. **Create a Puppet function** — overkill for two consumers

Recommendation: option 1 (duplicate). It's three lines and keeps profiles
independent.

## What Does NOT Change

- `profile::percona::bootstrap` — cluster bootstrap logic is version-agnostic
- `profile::percona::service` — `mysql` service name is the same for both
- Terraform module — already done (fact is passed via `cloud_init.tf`)
- Instance tags — already done (`percona:server_version` in `locals.tf`)

## Upgrade Path

A version upgrade (e.g., 8.0 → 8.4) happens as follows:

1. User changes `percona_server_version` in Terraform (e.g., `null` → `"latest"`)
2. Terraform updates `cloud_init` userdata → triggers ASG instance refresh
3. New instances boot with the new fact value
4. Puppet on the new instance:
   - Configures the correct repo (`ps-84-lts`)
   - Installs the correct package version
   - Starts MySQL with the new binary
5. ASG rolling refresh replaces instances one at a time
6. GTID replication handles data sync automatically

## Testing

After implementing, verify with `make test-keep` in `terraform-aws-percona-server`:
- Default (`null`): installs latest 8.0, `percona-xtrabackup-80`
- `"latest"`: installs latest 8.4, `percona-xtrabackup-84`
- `"8.0.45-36"`: installs exactly `8.0.45-36-1.noble`
- `"8.4.7-7"`: installs exactly `8.4.7-7-1.noble`
- `"8.4.7-7-1.noble"`: passes through unchanged