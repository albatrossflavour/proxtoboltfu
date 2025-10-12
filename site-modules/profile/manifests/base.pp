# Base SOE manifest
#
# @summary A base manifest which will be used on all nodes to set the SOE.
#  It includes many profile based on the kernel and os family of the node
# @example Declaring the class
#    include profile::base
#
class profile::base {
  contain profile::soe::hosts
  #contain profile::soe::cis
}
