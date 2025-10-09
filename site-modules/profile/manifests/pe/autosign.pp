# @summary
#	  Ausosigner test
#
# @example Basic usage
#   include profile::pe::autosign
#
class profile::pe::autosign {
    file { '/etc/puppetlabs/puppet/autosign.conf':
      ensure  => file,
      owner   => 'pe-puppet',
      group   => 'pe-puppet',
      mode    => '0644',
      content => "*.${facts['networking']['domain']}",
    }

    ini_setting { 'autosigning':
      setting => 'autosign',
      path    => '/etc/puppetlabs/puppet/puppet.conf',
      section => 'master',
      value   => 'true',
      notify  => Service['pe-puppetserver'],
    }
}
