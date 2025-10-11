# @summary Install and configure Nessus vulnerability scanner server
plan proxtoboltfu::build_nessus {

  # Lookup config from hiera
  $config = lookup('nessus::config', Hash, first, undef)

  # Lookup CSR attributes separately
  $csr_attributes = lookup('nessus::csr_attributes', Hash, first, {
    'datacenter' => 'lab',
    'role' => 'role::pe::nessus',
    'environment' => 'production'
  })

  # Get target from hiera config
  $target_host = $config['resolvable_hostname']
  $targets = get_targets($target_host)

  # Get puppet server from existing peadm config
  $peadm_config = lookup('peadm::config', Hash, first, undef)
  $puppet_server = $peadm_config['primary_host']

  out::message("Building Nessus Infrastructure")
  out::message("Target: ${targets}")
  out::message("Puppet Server: ${puppet_server}")
  out::message("")

  # Check if Puppet is already installed
  out::message("Checking if Puppet is already installed...")
  $check_puppet = run_command('test -f /usr/local/bin/puppet', $targets, '_catch_errors' => true)

  if $check_puppet.ok {
    out::message("✓ Puppet already installed on ${targets}, skipping installation")
    return { status => 'already_installed' }
  }

  out::message("Puppet not found, proceeding with installation...")

  # Insert CSR extension requests for Nessus classification
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

  out::message("Nessus build completed successfully")

  return { status => 'completed' }
}
