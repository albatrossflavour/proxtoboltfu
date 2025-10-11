# @summary Orchestrate full environment build
# @param apply_terraform Whether to run tofu apply first (default: true)
plan proxtoboltfu::build_environment (
  Boolean $apply_terraform = true
) {

  out::message("=== proxtoboltfu Environment Build ===")
  out::message("")

  # Step 1: Apply OpenTofu to provision infrastructure
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
  out::message("✓ Puppet Enterprise build complete (includes CA cert and console login)")
  out::message("")

  # Step 3: Build additional infrastructure servers
  out::message("Step 3: Building additional infrastructure servers...")

  # Get fresh inventory from tofu state (inventory is cached from plan start)
  $scm_inventory = run_task('proxtoboltfu::tofu_inventory', 'localhost',
    'dir' => 'tf',
    'tag_filter' => 'scm'
  )
  $cd4pe_inventory = run_task('proxtoboltfu::tofu_inventory', 'localhost',
    'dir' => 'tf',
    'tag_filter' => 'cd4pe'
  )
  $dashboard_inventory = run_task('proxtoboltfu::tofu_inventory', 'localhost',
    'dir' => 'tf',
    'tag_filter' => 'dashboard'
  )
  $nessus_inventory = run_task('proxtoboltfu::tofu_inventory', 'localhost',
    'dir' => 'tf',
    'tag_filter' => 'nessus'
  )

  $scm_data = $scm_inventory.first.value['value']
  $cd4pe_data = $cd4pe_inventory.first.value['value']
  $dashboard_data = $dashboard_inventory.first.value['value']
  $nessus_data = $nessus_inventory.first.value['value']

  # Create Target objects from fresh inventory
  $scm_targets = $scm_data.map |$t| { Target.new($t['name'], $t['uri']) }
  $cd4pe_targets = $cd4pe_data.map |$t| { Target.new($t['name'], $t['uri']) }
  $dashboard_targets = $dashboard_data.map |$t| { Target.new($t['name'], $t['uri']) }
  $nessus_targets = $nessus_data.map |$t| { Target.new($t['name'], $t['uri']) }

  if $scm_targets.empty and $cd4pe_targets.empty and $dashboard_targets.empty and $nessus_targets.empty {
    out::message("⚠ No additional infrastructure servers found in tofu state, skipping")
  } else {
    # Build all in parallel using background jobs
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

    $dashboard_job = background() || {
      if !$dashboard_targets.empty {
        out::message("  Building Dashboard server...")
        run_plan('proxtoboltfu::build_dashboard')
        out::message("  ✓ Dashboard build complete")
      }
    }

    $nessus_job = background() || {
      if !$nessus_targets.empty {
        out::message("  Building Nessus server...")
        run_plan('proxtoboltfu::build_nessus')
        out::message("  ✓ Nessus build complete")
      }
    }

    # Wait for all to complete
    wait([$scm_job, $cd4pe_job, $dashboard_job, $nessus_job])
    out::message("✓ Additional infrastructure servers build complete")
  }

  out::message("")

  # Step 4: Build agents if any exist
  out::message("Step 4: Building agent nodes...")

  # Get fresh inventory from tofu state
  $agent_inventory = run_task('proxtoboltfu::tofu_inventory', 'localhost',
    'dir' => 'tf',
    'tag_filter' => 'puppetagents'
  )

  $agent_data = $agent_inventory.first.value['value']
  $agent_targets = $agent_data.map |$t| { Target.new($t['name'], $t['uri']) }

  if $agent_targets.empty {
    out::message("⚠ No agent nodes found in tofu state, skipping")
  } else {
    out::message("Found ${agent_targets.length} agent node(s), building...")
    run_plan('proxtoboltfu::build_agents')
    out::message("✓ Agent build complete")
  }

  out::message("")
  out::message("=== Environment Build Complete ===")
  out::message("")
  out::message("Summary:")
  out::message("  ✓ Infrastructure provisioned")
  out::message("  ✓ Puppet Enterprise installed and configured (with CA cert and console access)")
  if !$scm_targets.empty or !$cd4pe_targets.empty or !$dashboard_targets.empty or !$nessus_targets.empty {
    out::message("  ✓ Additional infrastructure servers configured")
  }
  if !$agent_targets.empty {
    out::message("  ✓ ${agent_targets.length} agent nodes built")
  }

  return {
    status => 'completed',
    scm_count => $scm_targets.length,
    cd4pe_count => $cd4pe_targets.length,
    dashboard_count => $dashboard_targets.length,
    nessus_count => $nessus_targets.length,
    agent_count => $agent_targets.length
  }
}
