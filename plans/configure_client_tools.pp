# @summary Configure Puppet client tools to use the new PE server
plan igor::configure_client_tools {

  # Lookup PE config from hiera
  $peadm_config = lookup('peadm::config', Hash, first, undef)
  $pe_server = $peadm_config['primary_host']

  $cert_path = "/Users/${system::env('USER')}/.puppetlabs/etc/puppet/ssl/${pe_server}.pem"
  $token_path = "/Users/${system::env('USER')}/.puppetlabs/token-${pe_server}"
  $config_dir = "/Users/${system::env('USER')}/.puppetlabs/client-tools"

  out::message("Configuring Puppet client tools for ${pe_server}")

  # Ensure config directory exists
  run_command("mkdir -p ${config_dir}", 'localhost', '_run_as' => system::env('USER'))

  # Configure puppet-code (Code Manager)
  $code_config = @("EOCODE")
    {
      "service-url": "https://${pe_server}:8170/code-manager",
      "certificate-file": "${cert_path}",
      "cacert": "${cert_path}"
    }
    | EOCODE

  run_command("cat > ${config_dir}/puppet-code.conf << 'EOF'\n${code_config}EOF", 'localhost', '_run_as' => system::env('USER'))

  # Configure puppet-access (RBAC)
  $access_config = @("EOACCESS")
    {
        "service-url": "https://${pe_server}:4433/rbac-api",
        "token-file": "${token_path}",
        "certificate-file": "${cert_path}"
    }
    | EOACCESS

  run_command("cat > ${config_dir}/puppet-access.conf << 'EOF'\n${access_config}EOF", 'localhost', '_run_as' => system::env('USER'))

  # Configure puppetdb
  $puppetdb_config = @("EOPUPPETDB")
    {
      "puppetdb": {
        "server_urls": "https://${pe_server}:8081",
        "token-file": "${token_path}",
        "cacert": "${cert_path}"
      }
    }
    | EOPUPPETDB

  run_command("cat > ${config_dir}/puppetdb.conf << 'EOF'\n${puppetdb_config}EOF", 'localhost', '_run_as' => system::env('USER'))

  # Configure orchestrator
  $orchestrator_config = @("EOORCHESTRATOR")
    {
      "options" : {
        "service-url": "https://${pe_server}:8143",
        "token-file": "${token_path}",
        "cacert": "${cert_path}"
      }
    }
    | EOORCHESTRATOR

  run_command("cat > ${config_dir}/orchestrator.conf << 'EOF'\n${orchestrator_config}EOF", 'localhost', '_run_as' => system::env('USER'))

  out::message("Client tools configured successfully:")
  out::message("  ✓ puppet-code (Code Manager)")
  out::message("  ✓ puppet-access (RBAC)")
  out::message("  ✓ puppetdb")
  out::message("  ✓ orchestrator")

  return({ status => 'completed' })
}
