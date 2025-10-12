# @summary
#   A profile for PE primary
# @example
#   include role::pe::primary
#
# Sets up the firewall, backups and puppet strings
class profile::pe::primary {
  package { 'toml-rb':
    provider => 'puppetserver_gem',
    ensure   => installed,
    notify => Service['pe-puppetserver'],
  }
  include profile::pe::autosign
  include profile::pe::agent_types
}
