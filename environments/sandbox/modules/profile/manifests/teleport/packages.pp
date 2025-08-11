# @summary: Installs Teleport packages.
class profile::teleport::packages (
) {

  package { [
    'teleport',
  ]:
    ensure  => present,
  }

}
