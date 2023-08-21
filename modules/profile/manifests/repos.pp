# @summary: Configures APT and repositories
class profile::repos () {
  class { 'apt':
    stage  => init,
    update => {
      frequency => 'always',
    },
  }
}
