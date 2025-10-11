# @summary Install and configure SCM server
plan proxtoboltfu::build_scm {

  # Lookup config from hiera
  $config = lookup('complyadm::config', Hash, first, undef)

  # Lookup CSR attributes separately
  $csr_attributes = lookup('complyadm::csr_attributes', Hash, first, {
    'datacenter' => 'lab',
    'role' => 'role::pe::scm',
    'environment' => 'production'
  })

  # Get target from hiera config
  $target_host = $config['resolvable_hostname']
  $targets = get_targets($target_host)

  # Get puppet server from existing peadm config
  $peadm_config = lookup('peadm::config', Hash, first, undef)
  $puppet_server = $peadm_config['primary_host']

  out::message("Building SCM Infrastructure")
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

  # Insert CSR extension requests for SCM classification
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

  # Install using complyadm module from existing hiera config
  out::message("Installing SCM from config (data/scm.yaml)")
  run_plan('complyadm::install_from_config')

  # Run Puppet twice to ensure configuration converges
  out::message("Running Puppet agent to apply configuration")
  run_task('peadm::puppet_runonce', $targets)

  out::message("Running Puppet agent second time to ensure convergence")
  run_task('peadm::puppet_runonce', $targets)

  out::message("SCM build completed successfully")

  return { status => 'completed' }
}
