# @summary Orchestrate full environment build
# @param apply_terraform Whether to run tofu apply first (default: true)
plan proxtoboltfu::build_environment (
  Boolean $apply_terraform = true
) {

  out::message("=== proxtoboltfu Environment Build ===")
  out::message("")

  # Step 1: Apply Terraform to provision infrastructure
  if $apply_terraform {
    out::message("Step 1: Provisioning infrastructure with OpenTofu...")
    $tofu_result = run_command(
      'cd tf && tofu apply -auto-approve',
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    if $tofu_result.ok {
      out::message("✓ Infrastructure provisioned successfully")
      out::message("Waiting 30 seconds for DNS propagation...")
      ctrl::sleep(30)
    } else {
      fail_plan("Infrastructure provisioning failed: ${tofu_result.first.error}")
    }
  } else {
    out::message("Step 1: Skipping infrastructure provisioning (apply_terraform=false)")
  }

  out::message("")

  # Step 2: Build Puppet Enterprise
  out::message("Step 2: Building Puppet Enterprise...")
  run_plan('proxtoboltfu::build_pe')
  out::message("✓ Puppet Enterprise build complete")
  out::message("")

  # Step 3: Fetch CA certificate from PE server
  out::message("Step 3: Fetching CA certificate...")
  run_plan('proxtoboltfu::fetch_ca_cert')
  out::message("✓ CA certificate downloaded")
  out::message("")

  # Step 4: Login to PE console
  out::message("Step 4: Logging into Puppet Enterprise console...")
  run_plan('proxtoboltfu::puppet_access_login')
  out::message("✓ Console login complete")
  out::message("")

  # Step 5: Build SCM and CD4PE
  out::message("Step 5: Building SCM and CD4PE servers...")

  # Check if SCM and CD4PE targets exist in inventory
  $scm_targets = get_targets('scm-nodes')
  $cd4pe_targets = get_targets('cd4pe-nodes')

  if $scm_targets.empty and $cd4pe_targets.empty {
    out::message("⚠ No SCM or CD4PE targets found in inventory, skipping")
  } else {
    # Build both in parallel using background jobs
    $scm_job = background() || {
      if !$scm_targets.empty {
        out::message("  Building SCM server...")
        run_plan('proxtoboltfu::build_scm')
        out::message("  ✓ SCM build complete")
      }
    }

    $cd4pe_job = background() || {
      if !$cd4pe_targets.empty {
        out::message("  Building CD4PE server...")
        run_plan('proxtoboltfu::build_cd4pe')
        out::message("  ✓ CD4PE build complete")
      }
    }

    # Wait for both to complete
    wait($scm_job, $cd4pe_job)
    out::message("✓ SCM and CD4PE builds complete")
  }

  out::message("")

  # Step 6: Provision agents if any exist
  out::message("Step 6: Checking for agent nodes...")
  $agent_targets = get_targets('puppet-agents')

  if $agent_targets.empty {
    out::message("⚠ No agent nodes found in inventory, skipping agent provisioning")
  } else {
    out::message("Found ${agent_targets.length} agent node(s), provisioning...")
    # TODO: Add agent provisioning plan when created
    # run_plan('proxtoboltfu::provision_agents')
    out::message("⚠ Agent provisioning plan not yet implemented")
  }

  out::message("")
  out::message("=== Environment Build Complete ===")
  out::message("")
  out::message("Summary:")
  out::message("  ✓ Infrastructure provisioned")
  out::message("  ✓ Puppet Enterprise installed and configured")
  out::message("  ✓ CA certificate downloaded")
  out::message("  ✓ Console access configured")
  if !$scm_targets.empty or !$cd4pe_targets.empty {
    out::message("  ✓ SCM/CD4PE servers configured")
  }
  if !$agent_targets.empty {
    out::message("  ⚠ Agent nodes detected but provisioning not implemented")
  }

  return {
    status => 'completed',
    infrastructure_count => get_targets('puppet-infrastructure').length,
    agent_count => $agent_targets.length
  }
}
