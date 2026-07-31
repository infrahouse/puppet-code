# @summary: Configures APT and repositories
class profile::repos () {
  class { 'apt':
    stage  => init,
    update => {
      frequency => 'always',
      tries     => 5,
    },
  }

  # Also in the init stage: the lock timeout has to be in place before anything in
  # stage main starts installing packages. See the class for why apt-get needs an
  # unscoped key of its own.
  class { 'profile::apt_lock_timeout':
    stage => init,
  }
}
