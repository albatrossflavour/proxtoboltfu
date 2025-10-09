# @summary Install and configure metrics dashboard server with Grafana
# @param targets Target nodes to install dashboard on (default: dashboard.lab.albatrossflavour.com)
# @param puppet_server Puppet master server for agent installation (default: puppet.lab.albatrossflavour.com)
# @param grafana_admin_password Admin password for Grafana (default: s3ndmail)
plan proxtoboltfu::build_dashboard (
  TargetSpec $targets = 'dashboard.lab.albatrossflavour.com',
  String $puppet_server = 'puppet.lab.albatrossflavour.com',
  String $grafana_admin_password = 'grafana'
) {

  out::message("🔧 Building Dashboard Infrastructure")
  out::message("Target: ${targets}")
  out::message("Puppet Server: ${puppet_server}")
  out::message("")

  # Insert CSR extension requests for Dashboard classification
  out::message("📝 Setting up CSR extension requests...")
  $extension_requests = {
    'pp_datacenter' => 'lab',
    'pp_role' => 'role::pe::metric_dashboard',
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

  # Reset Grafana admin password
  out::message("🔐 Resetting Grafana admin password...")
  run_command("grafana-cli admin reset-admin-password ${grafana_admin_password}", $targets,
    '_run_as' => 'root'
  )

  # Run Puppet agent to apply dashboard configuration
  out::message("🎭 Running Puppet agent to apply dashboard configuration...")
  run_task('peadm::puppet_runonce', $targets)

  out::message("✅ Dashboard build completed successfully")
  out::message("📊 Grafana admin password: ${grafana_admin_password}")

  return { status => 'completed' }
}
