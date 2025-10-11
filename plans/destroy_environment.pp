# @summary Orchestrate full environment destruction
# @param confirm Set to true to actually destroy (default: false as safety measure)
plan proxtoboltfu::destroy_environment (
  Boolean $confirm = false
) {

  if !$confirm {
    out::message("=== Destroy Environment (Dry Run) ===")
    out::message("")
    out::message("This is a DRY RUN. To actually destroy, run:")
    out::message("  bolt plan run proxtoboltfu::destroy_environment confirm=true")
    out::message("")
    out::message("This will:")
    out::message("  1. Purge all client nodes from Puppet")
    out::message("  2. Destroy all infrastructure with OpenTofu")
    out::message("")
    return { status => 'dry_run' }
  }

  out::message("=== proxtoboltfu Environment Destruction ===")
  out::message("")

  # Step 1: Destroy client nodes if they exist
  out::message("Step 1: Checking for client nodes...")

  # Get fresh inventory from tofu state
  $agent_inventory = run_task('proxtoboltfu::tofu_inventory', 'localhost',
    'dir' => 'tf',
    'tag_filter' => 'puppetagents',
    '_catch_errors' => true
  )

  if $agent_inventory.ok {
    $agent_data = $agent_inventory.first.value['value']

    if $agent_data.empty {
      out::message("⚠ No agent nodes found in tofu state, skipping")
    } else {
      out::message("Found ${agent_data.length} agent node(s), destroying...")
      run_plan('proxtoboltfu::destroy_clients', {'confirm' => true})
      out::message("✓ Client nodes destroyed")
    }
  } else {
    out::message("⚠ Could not query inventory (infrastructure may not exist), skipping client destruction")
  }

  out::message("")

  # Step 2: Destroy infrastructure with OpenTofu
  out::message("Step 2: Destroying infrastructure with OpenTofu...")

  # Show what will be destroyed
  $plan_result = run_command(
    'cd tf && tofu plan -destroy',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if !$plan_result.ok {
    out::message("⚠ Warning: tofu plan -destroy failed, attempting destroy anyway...")
  }

  # Destroy infrastructure
  $tofu_result = run_command(
    'cd tf && tofu destroy -auto-approve',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $tofu_result.ok {
    out::message("✓ Infrastructure destroyed successfully")
  } else {
    fail_plan("Infrastructure destruction failed: ${tofu_result.first.error}")
  }

  out::message("")
  out::message("=== Environment Destruction Complete ===")
  out::message("")
  out::message("Summary:")
  out::message("  ✓ Client nodes purged from Puppet")
  out::message("  ✓ Infrastructure destroyed")

  return {
    status => 'completed'
  }
}
