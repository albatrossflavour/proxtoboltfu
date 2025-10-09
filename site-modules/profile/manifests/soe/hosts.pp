# @summary
#   Ensure the values in /etc/hosts are valid and managed
# @example Basic usage
#   include profile::soe::hosts
#
# @example Hiera values
#   profile::soe::hosts::purge: false
#
# The host file will be purged of unmanaged entries by default, the hiera value
# `profile::soe::hosts::purge` controls this.
#
class profile::soe::hosts {

  # Should we purge none-managed entries from the host file?
  $purge  = lookup('profile::soe::hosts::purge',Boolean,first,true)

  @@host { $facts['networking']['hostname']:
    ensure       => present,
    host_aliases => [$facts['networking']['fqdn']],
    ip           => $facts['networking']['ip'],
    tag          => $facts['networking']['domain'],
  }

  # Collect all of the exported host resources
  Host <<| tag == $facts['networking']['domain'] |>>

  if $purge {
    resources { 'host':
      purge => true,
    }
  }
}
