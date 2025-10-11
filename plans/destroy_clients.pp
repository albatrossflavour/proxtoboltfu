# @summary Destroy puppet agent clients using OpenTofu
# @param confirm Safety confirmation (must be true to proceed with destroy)
plan proxtoboltfu::destroy_clients (
  Boolean $confirm = false
) {

  out::message('=== Puppet Agent Clients Destroy Plan ===')
  out::message('')

  # Get current agent inventory to show what will be destroyed
  $agent_inventory = run_task('proxtoboltfu::tofu_inventory', 'localhost',
    'dir' => 'tf',
    'tag_filter' => 'puppetagents'
  )

  $agent_data = $agent_inventory.first.value['value']
  $agent_count = $agent_data.length

  if $agent_count == 0 {
    out::message('⚠ No agent nodes found in tofu state')
    return { status => 'no_agents', agent_count => 0 }
  }

  out::message("Found ${agent_count} agent node(s) to destroy:")
  $agent_data.each |$agent| {
    out::message("  - ${agent['name']} (${agent['uri']})")
  }
  out::message('')

  # Check if we should proceed with destroy
  unless $confirm {
    out::message('To proceed with destroy, run:')
    out::message('  bolt plan run proxtoboltfu::destroy_clients confirm=true')
    return {
      status => 'plan_only',
      agent_count => $agent_count
    }
  }

  # Destroy using OpenTofu with target flag for puppet_clients resource
  out::message('Running tofu destroy for puppet_clients...')
  $destroy_result = run_command(
    'cd tf && tofu destroy -target=proxmox_vm_qemu.puppet_clients -target=pihole_dns_record.puppet_clients -auto-approve',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $destroy_result.ok {
    out::message('✓ Puppet agent clients destroyed successfully')
    out::message('')
    out::message("Destroyed ${agent_count} agent node(s)")
  } else {
    fail_plan("Failed to destroy clients: ${destroy_result.first.error}")
  }

  return {
    status => 'destroyed',
    agent_count => $agent_count
  }
}
