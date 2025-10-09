# @summary Remove all VM templates and generated Terraform files
# @param confirm_cleanup Require explicit confirmation to prevent accidents (default: false)
plan proxtoboltfu::clean_templates (
  Boolean $confirm_cleanup = false
) {

  out::message("🧹 Cleaning Proxmox VM Templates")
  out::message("This will remove ALL templates and generated Terraform files")
  out::message("")

  unless $confirm_cleanup {
    fail("Template cleanup requires explicit confirmation. Use: bolt plan run proxtoboltfu::clean_templates confirm_cleanup=true")
  }

  out::message("⚠️  CONFIRMED: Proceeding with template cleanup")
  out::message("")

  # Run template cleanup script
  out::message("🗑️  Starting template cleanup process...")
  $cleanup_result = run_command('cd .scripts && ./template-clean.sh', 'localhost',
    '_catch_errors' => true,
    '_run_as' => 'root'
  )

  unless $cleanup_result.ok {
    out::message("❌ Template cleanup failed")
    $cleanup_result.each |$result| {
      if $result.error {
        out::message("Error: ${result.error}")
      }
      if $result.value and $result.value['stderr'] {
        out::message("Stderr: ${result.value['stderr']}")
      }
    }
    fail("Template cleanup failed")
  }

  # Display results
  out::message("✅ Template cleanup completed successfully")
  $cleanup_result.each |$result| {
    if $result.value['stdout'] {
      out::message("Output:")
      out::message($result.value['stdout'])
    }
  }

  out::message("")
  out::message("🎯 All templates have been removed")

  return { status => 'completed' }
}
