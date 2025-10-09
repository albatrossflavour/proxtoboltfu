# @summary
#   A base role which will be applied to all puppetmasters
# @example
#   include role::puppetmaster
#
# Sets up the firewall, backups and puppet strings
class role::pe::cd4pe {
  require profile::base
  include profile::pe::cd4pe
}
