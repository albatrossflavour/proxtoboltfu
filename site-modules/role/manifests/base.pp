# @summary
#   A base role which will be applied to all nodes in order to apply the base SOE settings
# @example
#   include role::base
#
# This role should be applied to any of the enforced nodes.  It will cope with Linux and Windows
# at this point.
class role::base {
  require profile::base
}
