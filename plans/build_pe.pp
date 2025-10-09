# @summary Install and configure Puppet Enterprise master server
plan proxtoboltfu::build_pe {

  $params = lookup('peadm::config', Hash, first, undef)

  # Lookup CSR attributes separately with defaults
  $csr_attributes = lookup('peadm::csr_attributes', Hash, first, {
    'datacenter' => 'lab',
    'role' => 'role::pe::primary',
    'environment' => 'production'
  })

  $targets = get_targets($params['primary_host'])

  out::message("Building Puppet Enterprise Infrastructure")
  out::message("Target: ${targets}")
  out::message("")

  # Insert CSR extension requests for PE classification
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

  run_plan('peadm::install', $params)

  # Deploy code to production environment
  out::message("Deploying code to production environment...")
  run_task('peadm::code_manager', $targets,
    'action' => 'deploy production'
  )

  # Deploy code to development environment
  out::message("Deploying code to development environment...")
  run_task('peadm::code_manager', $targets,
    'action' => 'deploy development'
  )

  # Install eyaml keys for encrypted data
  out::message("Installing eyaml encryption keys...")

  # Read public key content
  $public_key_content = file::read("keys/public_key.pkcs7.pem")
  run_task('peadm::mkdir_p_file', $targets,
    'content' => $public_key_content,
    'path' => '/etc/puppetlabs/secure/keys/public_key.pkcs7.pem',
    'owner' => 'pe-puppet',
    'mode' => '0640',
    'group' => 'pe-puppet',
    'chown_r' => '/etc/puppetlabs/secure'
  )

  # Read private key content
  $private_key_content = file::read("keys/private_key.pkcs7.pem")
  run_task('peadm::mkdir_p_file', $targets,
    'content' => $private_key_content,
    'path' => '/etc/puppetlabs/secure/keys/private_key.pkcs7.pem',
    'owner' => 'pe-puppet',
    'mode' => '0640',
    'group' => 'pe-puppet',
    'chown_r' => '/etc/puppetlabs/secure'
  )

  # Run Puppet twice to ensure configuration converges
  out::message("Running Puppet agent to apply configuration...")
  run_task('peadm::puppet_runonce', $targets)

  out::message("Running Puppet agent second time to ensure convergence...")
  run_task('peadm::puppet_runonce', $targets)

  # Start puppet service
  out::message("Starting Puppet service...")
  run_task('service', $targets,
    'name' => 'puppet',
    'action' => 'start'
  )

  out::message("Puppet Enterprise build completed successfully")

  return { status => 'completed' }
}
