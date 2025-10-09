# @summary
#   A base role which will be applied to all puppetmasters
# @example
#   include role::pe::nessus
#
# Sets up the firewall, backups and puppet strings
class role::pe::nessus {
  require profile::base
  contain profile::pe::nessus
}
