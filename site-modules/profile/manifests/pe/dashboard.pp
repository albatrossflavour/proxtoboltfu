# @summary
#   Setup the metric dashboard
# @example
#   include profile::pe::dashboard
class profile::pe::dashboard {
  #profile::soe::pinned_package { 'grafana':
  #  version        => 'grafana-8.5.20-1.x86_64',
  #  manage_package => false,
  #}

  #profile::soe::pinned_package { 'influxdb2':
  #  version        => 'influxdb2-2.6.1-1.x86_64',
  #  manage_package => false,
  #}

  profile::soe::pinned_package { 'telegraf':
    version        => 'telegraf-1.29.4-1.x86_64',
    manage_package => false,
  }


  #contain openssl
  include nginx
  include puppet_operational_dashboards

  class { 'prometheus::server':
    usershell      => '/sbin/nologin',
    version        => '2.52.0',
    scrape_configs => [
      {
        'job_name'        => 'puppet',
        'scrape_interval' => '60s',
        'scrape_timeout'  => '10s',
        'static_configs'  => [
          {
            'targets' => [ 'puppet.lab.albatrossflavour.com:9100' ],
            'labels'  => { 'alias' => 'Puppet', }
          }
        ],
      },
    ],
  }

  #openssl::certificate::x509 { 'hostcert':
  #  commonname => $facts['networking']['fqdn'],
  #}

  nginx::resource::server { 'dashboard.lab.albatrossflavour.com':
    ssl         => false,
    #ssl_port    => 443,
    listen_port => 80,
    #ssl_cert    => '/etc/ssl/certs/hostcert.crt',
    #ssl_key     => '/etc/ssl/certs/hostcert.key',
    proxy       => 'http://localhost:3000',
  }
}
