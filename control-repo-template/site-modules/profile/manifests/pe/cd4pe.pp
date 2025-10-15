# @summary
#   Setup a cdpe instance
# @example
#   include profile::pe::cd4pe
class profile::pe::cd4pe {

  group { 'docker':
    ensure => present,
  }

}
