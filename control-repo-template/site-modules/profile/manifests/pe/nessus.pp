# @summary
#	  Puppet Data Collector profile
#
# @example Basic usage
#   include profile::pe::nessus
#
class profile::pe::nessus (
  $nessus_path = '/opt/nessus',
  $nessus_base_url = 'https://www.tenable.com/downloads/api/v2/pages/nessus/files',
  $nessus_package = 'Nessus-10.10.0-ubuntu1604_amd64.deb',
  $nessus_server = 'new-nessus.albatrossflavour.com',
  $nessus_scan_name = 'patches',
  $nessus_package_checksum = '35b023fa315cba66bc60a47761851b50',
){

  file { $nessus_path:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
  }

  file { "${nessus_path}/${nessus_package}":
    ensure         => file,
    owner          => 'root',
    group          => 'root',
    mode           => '0644',
    source         => "${nessus_base_url}/${nessus_package}",
    checksum       => 'md5',
    checksum_value => $nessus_package_checksum,
    require        => File[$nessus_path],
  }

  package { 'nessus':
    ensure    => installed,
    source    => "${nessus_path}/${nessus_package}",
    require   => File["${nessus_path}/${nessus_package}"],
    subscribe => File["${nessus_path}/${nessus_package}"],
  }

  service { 'nessusd':
    ensure    => running,
    enable    => true,
    hasstatus => true,
    subscribe => Package['nessus'],
  }

  class { 'nessus_transformer':
    scan_name                   => $nessus_scan_name,
    scan_reports_source_address => $nessus_server,
    require                     => Service['nessusd'],
  }

}
