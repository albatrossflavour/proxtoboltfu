# @summary Install and configure Nessus vulnerability scanner server
# @param targets Target nodes to install Nessus on (default: nessus.lab.albatrossflavour.com)
# @param puppet_server Puppet master server for agent installation (default: puppet.lab.albatrossflavour.com)

plan proxtoboltfu::build_nessus (
  TargetSpec $targets = 'nessus.lab.albatrossflavour.com',
  String $puppet_server = 'puppet.lab.albatrossflavour.com'
) {

  out::message("🔧 Building Nessus Infrastructure")
  out::message("Target: ${targets}")
  out::message("Puppet Server: ${puppet_server}")
  out::message("")

  # Insert CSR extension requests for Nessus classification
  out::message("📝 Setting up CSR extension requests...")
  $extension_requests = {
    'pp_datacenter' => 'lab',
    'pp_role' => 'role::pe::nessus',
    'pp_environment' => 'production'
  }

  run_plan('peadm::util::insert_csr_extension_requests',
    'extension_requests' => $extension_requests,
    'targets' => $targets
  )

  # Install Puppet agent
  out::message("🎭 Installing Puppet agent...")
  run_task('peadm::agent_install', $targets,
    'server' => $puppet_server
  )

  # Run Puppet agent to apply Nessus configuration
  out::message("🎭 Running Puppet agent to apply Nessus configuration...")
  run_task('peadm::puppet_runonce', $targets)

  out::message("✅ Nessus build completed successfully")
  out::message("🔍 Nessus scanner is ready for vulnerability assessments")

  return { status => 'completed' }
}
