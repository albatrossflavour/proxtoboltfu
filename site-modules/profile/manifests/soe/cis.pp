# @summary
#	  CIS Enforcement
#
# @example Basic usage
#   include profile::soe::cis
#
class profile::soe::cis {
  case $facts['kernel'] {
    'Linux': {
      include sce_linux
    }
    'windows': {
      include sce_windows
    }
    default: {  }
  }
}
