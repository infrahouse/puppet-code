# @summary: Configures APT and repositories
class profile::repos () {
  class { 'apt':
    update => {
      frequency => 'daily',
    },
  }
}
