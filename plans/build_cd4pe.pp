# @summary Install and configure CD4PE server
plan proxtoboltfu::build_cd4pe {

  # Lookup config from hiera
  $config = lookup('cd4peadm::config', Hash, first, undef)

  # Lookup CSR attributes separately
  $csr_attributes = lookup('cd4peadm::csr_attributes', Hash, first, {
    'datacenter' => 'lab',
    'role' => 'role::pe::cd4pe',
    'environment' => 'production'
  })

  # Get target from hiera config
  $target_host = $config['resolvable_hostname']
  $targets = get_targets($target_host)

  # Get puppet server from existing peadm config
  $peadm_config = lookup('peadm::config', Hash, first, undef)
  $puppet_server = $peadm_config['primary_host']

  out::message("Building CD4PE Infrastructure")
  out::message("Target: ${targets}")
  out::message("Puppet Server: ${puppet_server}")
  out::message("")

  # Insert CSR extension requests for CD4PE classification
  out::message("Setting up CSR extension requests...")

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
  out::message("Installing Puppet agent...")
  run_task('peadm::agent_install', $targets,
    'server' => $puppet_server
  )

  # Wait for automatic first run triggered by agent install to complete
  out::message("Waiting for automatic Puppet run to complete...")
  ctrl::sleep(60)

  # Run Puppet agent to register with master
  out::message("Running Puppet agent to register with master...")
  run_task('peadm::puppet_runonce', $targets)

  # Install CD4PE using cd4peadm module
  out::message("Installing CD4PE...")
  run_plan('cd4peadm::install')

  # Run Puppet twice to ensure configuration converges
  out::message("Running Puppet agent to apply configuration...")
  run_task('peadm::puppet_runonce', $targets)

  out::message("Running Puppet agent second time to ensure convergence...")
  run_task('peadm::puppet_runonce', $targets)

  out::message("CD4PE build completed successfully")

  return { status => 'completed' }
}
