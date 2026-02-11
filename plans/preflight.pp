# @summary Validate prerequisites before deployment
# @param provider Infrastructure provider (default: proxmox)
plan igor::preflight (
  String $provider = 'proxmox'
) {

  out::message('=== Igor Preflight Checks ===')
  out::message('')

  # 1. SSH key exists with correct permissions
  $ssh_key = '~/.ssh/igor'
  $ssh_check = run_command(
    "test -f ${ssh_key} && stat -f '%Lp' ${ssh_key}",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $ssh_check.ok {
    $ssh_perms = $ssh_check.first.value['stdout'].strip
    if $ssh_perms == '600' or $ssh_perms == '400' {
      out::message("  PASS: SSH key exists (${ssh_key}, mode ${ssh_perms})")
      $ssh_fail = []
    } else {
      out::message("  FAIL: SSH key has wrong permissions (${ssh_perms}, need 600 or 400)")
      $ssh_fail = ['ssh_permissions']
    }
  } else {
    out::message("  FAIL: SSH key not found (${ssh_key})")
    $ssh_fail = ['ssh_key']
  }

  # 2. tofu binary installed
  $tofu_check = run_command(
    'which tofu',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $tofu_check.ok {
    out::message('  PASS: tofu binary installed')
    $tofu_fail = []
  } else {
    out::message('  FAIL: tofu binary not found')
    $tofu_fail = ['tofu']
  }

  # 3. jq binary installed
  $jq_check = run_command(
    'which jq',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $jq_check.ok {
    out::message('  PASS: jq binary installed')
    $jq_fail = []
  } else {
    out::message('  FAIL: jq binary not found')
    $jq_fail = ['jq']
  }

  # 4. gh CLI installed and authenticated
  $gh_check = run_command(
    'which gh',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $gh_check.ok {
    $gh_auth = run_command(
      'gh auth status',
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    if $gh_auth.ok {
      out::message('  PASS: gh CLI installed and authenticated')
      $gh_fail = []
    } else {
      out::message('  FAIL: gh CLI installed but not authenticated (run: gh auth login)')
      $gh_fail = ['gh_auth']
    }
  } else {
    out::message('  FAIL: gh CLI not found (install: brew install gh)')
    $gh_fail = ['gh']
  }

  # 5. eyaml keys exist
  $eyaml_check = run_command(
    'test -f keys/private_key.pkcs7.pem && test -f keys/public_key.pkcs7.pem',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $eyaml_check.ok {
    out::message('  PASS: eyaml keys exist')
    $eyaml_fail = []
  } else {
    out::message('  FAIL: eyaml keys not found in keys/')
    $eyaml_fail = ['eyaml_keys']
  }

  # 6. Bolt modules installed
  $modules_check = run_command(
    'test -d .modules',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $modules_check.ok {
    out::message('  PASS: Bolt modules installed (.modules/ exists)')
    $modules_fail = []
  } else {
    out::message('  FAIL: Bolt modules not installed (run: bolt module install)')
    $modules_fail = ['bolt_modules']
  }

  # 7. tofu initialized for provider
  $provider_dir = "tf/providers/${provider}"
  $init_check = run_command(
    "test -d ${provider_dir}/.terraform",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $init_check.ok {
    out::message("  PASS: tofu initialized for ${provider}")
    $init_fail = []
  } else {
    out::message("  FAIL: tofu not initialized (run: cd ${provider_dir} && tofu init)")
    $init_fail = ['tofu_init']
  }

  # 8. Provider directory exists
  $provider_check = run_command(
    "test -d ${provider_dir}",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $provider_check.ok {
    out::message("  PASS: Provider directory exists (${provider_dir})")
    $provider_fail = []
  } else {
    out::message("  FAIL: Provider directory not found (${provider_dir})")
    $provider_fail = ['provider_dir']
  }

  # 9. File write permissions
  $write_check = run_command(
    'test -w .',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $write_check.ok {
    out::message('  PASS: Write permissions in working directory')
    $write_fail = []
  } else {
    out::message('  FAIL: No write permissions in working directory')
    $write_fail = ['write_permissions']
  }

  # Collect all failures
  $failures = $ssh_fail + $tofu_fail + $jq_fail + $gh_fail + $eyaml_fail + $modules_fail + $init_fail + $provider_fail + $write_fail

  out::message('')

  if $failures.empty {
    out::message('All preflight checks passed')
  } else {
    fail_plan("Preflight failed: ${failures.join(', ')}")
  }

  return({
    status => 'passed',
    checks_run => 9,
    failures => $failures
  })
}
