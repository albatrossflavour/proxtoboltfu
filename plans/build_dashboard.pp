# @summary Install and configure metrics dashboard server with Grafana
plan proxtoboltfu::build_dashboard {

  # Lookup config from hiera
  $config = lookup('dashboard::config', Hash, first, undef)

  # Lookup CSR attributes separately
  $csr_attributes = lookup('dashboard::csr_attributes', Hash, first, {
    'datacenter' => 'lab',
    'role' => 'role::dashboard',
    'environment' => 'production'
  })

  # Get target from hiera config
  $target_host = $config['resolvable_hostname']
  $targets = get_targets($target_host)

  # Get puppet server from existing peadm config
  $peadm_config = lookup('peadm::config', Hash, first, undef)
  $puppet_server = $peadm_config['primary_host']

  # Get grafana admin password from hiera
  $grafana_admin_password = lookup('dashboard::grafana_admin_password', String, first, 'grafana')

  out::message("Building Dashboard Infrastructure")
  out::message("Target: ${targets}")
  out::message("Puppet Server: ${puppet_server}")
  out::message("")

  # Insert CSR extension requests for Dashboard classification
  out::message("Setting up CSR extension requests")
  $extension_requests = {
    'pp_datacenter' => $csr_attributes['datacenter'],
    'pp_role' => $csr_attributes['role'],
    'pp_environment' => $csr_attributes['environment']
  }

  run_plan('peadm::util::insert_csr_extension_requests',
    'extension_requests' => $extension_requests,
    'targets' => $targets
  )

  # Install Puppet agent
  out::message("Installing Puppet agent")
  run_task('peadm::agent_install', $targets,
    'server' => $puppet_server
  )

  # Wait for automatic first run triggered by agent install to complete
  out::message("Waiting for automatic Puppet run to complete...")
  ctrl::sleep(60)

  # Run Puppet agent to register with master
  out::message("Running Puppet agent")
  run_task('peadm::puppet_runonce', $targets)

  # Run Puppet twice to ensure configuration converges
  out::message("Running Puppet agent to apply configuration")
  run_task('peadm::puppet_runonce', $targets)

  out::message("Running Puppet agent second time to ensure convergence")
  run_task('peadm::puppet_runonce', $targets)

  # Reset Grafana admin password
  out::message("Resetting Grafana admin password...")
  run_command("grafana-cli admin reset-admin-password ${grafana_admin_password}", $targets,
    '_run_as' => 'root'
  )

  out::message("Dashboard build completed successfully")
  out::message("Grafana admin password: ${grafana_admin_password}")

  return { status => 'completed' }
}
