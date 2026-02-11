# @summary Build puppet agent clients
plan igor::build_agents {

  # Get puppet server from peadm config
  $peadm_config = lookup('peadm::config', Hash, first, undef)
  $puppet_server = $peadm_config['primary_host']

  # Get fresh inventory from tofu state
  $agent_inventory = run_task('igor::tofu_inventory', 'localhost',
    'provider' => 'proxmox',
    'tag_filter' => 'puppetagents'
  )

  $agent_data = $agent_inventory.first.value['value']
  $agent_targets = $agent_data.map |$t| { Target.new($t['name'], $t['uri']) }

  if $agent_targets.empty {
    out::message("No agent nodes found in tofu state")
    return({ status => 'no_agents', agent_count => 0 })
  }

  out::message("Building Puppet Agents")
  out::message("Puppet Server: ${puppet_server}")
  out::message("Targets: ${agent_targets.length} agents")
  out::message("")

  # Process each agent
  $agent_targets.each |$target| {
    out::message("Provisioning ${target.name}...")

    # Extract OS family and environment from target name
    # Format: osFamily-version-puppet-environment-instance
    # Example: ubuntu-2204-puppet-prod-1
    $name_parts = $target.name.split('-')
    $environment = $name_parts[3]  # prod or dev

    # Insert CSR extension requests for agent classification
    $extension_requests = {
      'pp_datacenter' => 'lab',
      'pp_role' => 'role::base',
      'pp_environment' => $environment
    }

    run_plan('peadm::util::insert_csr_extension_requests',
      'extension_requests' => $extension_requests,
      'targets' => $target
    )

    # Install Puppet agent
    run_task('peadm::agent_install', $target,
      'server' => $puppet_server
    )

    out::message("  ✓ Agent installed on ${target.name}")
  }

  # Wait for automatic first runs to complete
  out::message("")
  out::message("Waiting for automatic Puppet runs to complete...")
  ctrl::sleep(60)

  # Run puppet agent on all targets to ensure convergence
  out::message("Running Puppet agent on all targets...")
  run_task('peadm::puppet_runonce', $agent_targets)

  out::message("")
  out::message("Agent build completed successfully")
  out::message("Built ${agent_targets.length} agents")

  return({
    status => 'completed',
    agent_count => $agent_targets.length
  })
}
