# @summary
#   Which agents to install
# @example
#   include profile::pe::agent_types
class profile::pe::agent_types {
  $agents = lookup('profile::pe::agent_types',Array,unique,[])

  class { $agents:
    #before => Class['profile::pe::node_groups'],
  }
}
