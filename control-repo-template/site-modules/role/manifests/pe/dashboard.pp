# @summary
#   A base role which will be applied to all dashboard
# @example
#   include role::pe::dashboard
#
class role::pe::dashboard {
  require profile::base
  include profile::pe::dashboard
}
