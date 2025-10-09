# @summary
#   A profile for PE primary
# @example
#   include role::pe::primary
#
# Sets up the firewall, backups and puppet strings
class profile::pe::primary {
  include profiles::pe::agent_types
}
