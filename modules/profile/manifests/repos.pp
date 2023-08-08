class profile::repos () {
  class { 'apt':
    update => {
      frequency => 'daily',
    },
  }
}
