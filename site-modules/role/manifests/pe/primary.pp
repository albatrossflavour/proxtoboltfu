# @summary
#   A base role which will be applied to all pes
# @example
#   include role::pe::primary
#
# Sets up the firewall, backups and puppet strings
class role::pe::primary {
  require profile::base
  include profile::pe::primary
}
