# @summary Run OpenTofu plan operations without terraform plugin interference
# @param terraform_dir Directory containing OpenTofu configuration
plan proxtoboltfu::tofu_plan (
  String $terraform_dir = 'tf'
) {

  out::message("📋 Running OpenTofu Plan")
  out::message("Directory: ${terraform_dir}")
  out::message("")

  # Run tofu plan directly on localhost
  out::message("🚀 Running tofu plan...")
  $plan_result = run_command("/opt/homebrew/bin/tofu -chdir=${terraform_dir} plan", 'localhost', '_catch_errors' => true)

  if $plan_result.ok {
    out::message("✅ OpenTofu plan completed successfully")
    out::message("")
    out::message("Plan Output:")
    out::message("--------------------------------------------------")
    $plan_result.each |$result| {
      out::message($result.value['stdout'])
      if $result.value['stderr'] and $result.value['stderr'] != '' {
        out::message("")
        out::message("Warnings/Errors:")
        out::message($result.value['stderr'])
      }
    }
  } else {
    out::message("❌ OpenTofu plan failed")
    $plan_result.each |$result| {
      if $result.error {
        out::message("Error: ${result.error}")
      }
      if $result.value and $result.value['stderr'] {
        out::message("Stderr: ${result.value['stderr']}")
      }
    }
    fail("OpenTofu plan failed")
  }

  return { status => 'completed' }
}
