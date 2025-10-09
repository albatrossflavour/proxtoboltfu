# @summary Generate VM templates from OS distributions using KFVEE numbering
# @param storage Storage backend for templates (default: ceph)
# @param force_regenerate Force regeneration of existing templates (default: false)
# @param templates_only Only create templates, skip Terraform file generation (default: false)
plan proxtoboltfu::generate_templates (
  String $storage = 'ceph',
  Boolean $force_regenerate = false,
  Boolean $templates_only = false
) {

  out::message("🏗️  Generating Proxmox VM Templates")
  out::message("Storage backend: ${storage}")
  out::message("Force regenerate: ${force_regenerate}")
  out::message("Templates only: ${templates_only}")
  out::message("")

  # Phase 1: Create templates on Proxmox
  out::message("📦 Phase 1: Creating VM templates on Proxmox...")
  
  # Validate prerequisites
  out::message("✅ Validating prerequisites...")

  # Check if required files exist (using absolute paths)
  $project_root = system::env('PWD')
  unless file::exists("${project_root}/config/templates.csv") {
    fail("Templates configuration file not found: ${project_root}/config/templates.csv")
  }
  
  unless file::exists("${project_root}/.scripts/template-generate.sh") {
    fail("Template generation script not found: ${project_root}/.scripts/template-generate.sh")
  }

  # Upload templates.csv to Proxmox host
  out::message("📤 Uploading templates configuration...")
  upload_file("${project_root}/config/templates.csv", '/tmp/templates.csv', '192.168.5.10')

  # Set up environment variables and arguments for the script
  $script_env = {
    'STORAGE' => $storage,
    'FORCE' => $force_regenerate,
    'TEMPLATES' => '/tmp/templates.csv'
  }

  # Set up the complete working environment
  out::message("🔧 Setting up working environment...")
  $setup_result = run_command(@("SETUP_ENV")
    # Create proper directory structure
    mkdir -p /root/templates
    cd /root/templates
    
    # Copy the CSV file to the expected location
    cp /tmp/templates.csv ./templates.csv
    
    # Create config file if it doesn't exist
    if [ ! -f ./config ]; then
      echo "changeme" > ./config
      echo "Created default config file with password 'changeme'"
    fi
    
    # Verify setup
    echo "Working directory setup:"
    pwd
    ls -la
    | SETUP_ENV
  , '192.168.5.10', '_catch_errors' => true)

  unless $setup_result.ok {
    fail("Failed to set up working environment on Proxmox host")
  }

  # Upload the script to the working directory
  out::message("📤 Uploading script to working directory...")
  upload_file("${project_root}/.scripts/template-generate.sh", '/root/templates/template-generate.sh', '192.168.5.10')
  
  # Make it executable
  run_command('chmod +x /root/templates/template-generate.sh', '192.168.5.10')

  # Update environment to use local file
  $script_env_updated = {
    'STORAGE' => $storage,
    'FORCE' => $force_regenerate,
    'TEMPLATES' => './templates.csv'
  }

  # Run the template generation script from the proper working directory
  out::message("🚀 Running template generation script...")
  $generation_result = run_command(
    'cd /root/templates && ./template-generate.sh', 
    '192.168.5.10',
    '_env_vars' => $script_env_updated,
    '_catch_errors' => true
  )

  unless $generation_result.ok {
    out::message("❌ Template generation failed")
    $generation_result.each |$result| {
      if $result.error {
        out::message("Error: ${result.error}")
      }
      if $result.value and $result.value['stderr'] {
        out::message("Stderr: ${result.value['stderr']}")
      }
    }
    fail("Template generation failed")
  }

  # Display results
  out::message("✅ Template generation completed successfully")
  $generation_result.each |$result| {
    if $result.value['stdout'] {
      out::message("Output:")
      out::message($result.value['stdout'])
    }
  }

  # Phase 2: Generate Terraform files locally (only if templates succeeded)
  unless $templates_only {
    out::message("")
    out::message("📄 Phase 2: Generating Terraform files locally...")
    
    # Query Proxmox to get actual created template IDs and names
    out::message("🔍 Querying Proxmox for created templates...")
    $template_query = run_command(
      'qm list --full | grep "template-" | awk \'{print $1","$2","$3}\'',
      '192.168.5.10',
      '_catch_errors' => true
    )
    
    if $template_query.ok {
      $template_data = $template_query.first.value['stdout']
      out::message("Found templates: ${template_data}")
      
      # Generate Terraform files based on actual templates that exist
      out::message("📝 Generating Terraform configuration files...")
      run_plan('proxtoboltfu::generate_terraform_files_simple',
        'template_data' => $template_data,
        'storage' => $storage
      )
      
      out::message("✅ Terraform files generated successfully")
    } else {
      out::message("⚠️  Could not query templates from Proxmox, skipping Terraform generation")
    }
  }

  out::message("")
  out::message("🎯 Template generation process completed")
  
  $final_status = $templates_only ? {
    true  => 'templates_created',
    false => 'completed_with_terraform'
  }

  return { 
    status => $final_status, 
    storage => $storage,
    templates_only => $templates_only 
  }
}
