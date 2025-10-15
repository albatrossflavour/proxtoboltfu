# @summary Generate PE RBAC token for Nessus Transformer
# @param regenerate Whether to regenerate token even if one exists (default: false)
# @param commit_changes Whether to git commit and push the updated nessus.yaml (default: false)
# @param work_dir Directory containing control repo (default: ~/dev)
plan proxtoboltfu::generate_nessus_pe_token (
  Boolean $regenerate = false,
  Boolean $commit_changes = false,
  String $work_dir = '~/dev'
) {

  out::message("Checking for existing Nessus Transformer PE token...")

  # Try to lookup existing token
  $existing_token = lookup('nessus_transformer::pe_token', Optional[String], 'first', undef)

  # Check if we should skip generation
  if $existing_token and $existing_token != '~' and !$regenerate {
    out::message("✓ Nessus Transformer PE token already exists (use regenerate=true to force regeneration)")
    return { status => 'skipped', reason => 'token_exists' }
  }

  if $regenerate {
    out::message("Regenerating Nessus Transformer PE token...")
  } else {
    out::message("Generating Nessus Transformer PE token...")
  }

  # Lookup PE server and console password from hiera
  $pe_params = lookup('peadm::config', Hash, first, undef)
  $console_password = $pe_params['console_password']
  $pe_server = $pe_params['primary_host']

  # Generate token via PE RBAC API
  out::message("  Requesting token from PE RBAC API...")

  $token_request = @("EOT")
    curl -sk -X POST "https://${pe_server}:4433/rbac-api/v1/auth/token" \
      -H "Content-Type: application/json" \
      -d '{
        "login": "admin",
        "password": ${console_password.to_json},
        "lifetime": "10y",
        "description": "nessus_transformer automation token"
      }' | jq -r '.token'
    | EOT

  $token_result = run_command(
    $token_request,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $token_result.ok {
    fail_plan("Failed to generate PE token: ${token_result.first.error}")
  }

  $pe_token = $token_result.first.value['stdout'].strip

  if $pe_token == '' or $pe_token == 'null' {
    fail_plan("Failed to generate PE token: empty response from RBAC API")
  }

  out::message("  ✓ PE token generated successfully")

  # Encrypt token with eyaml
  out::message("  Encrypting token with eyaml...")

  $encrypt_cmd = "echo '${pe_token}' | eyaml encrypt --stdin --pkcs7-private-key=keys/private_key.pkcs7.pem --pkcs7-public-key=keys/public_key.pkcs7.pem | grep 'ENC\\[' | head -n 1 | sed 's/^string: //'"

  $encrypt_result = run_command(
    $encrypt_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $encrypt_result.ok {
    fail_plan("Failed to encrypt PE token: ${encrypt_result.first.error}")
  }

  $encrypted_token = $encrypt_result.first.value['stdout'].strip

  out::message("  ✓ Token encrypted successfully")

  # Determine where to write the token
  $control_repo_name = lookup('pe_control_repo_name', String, first, 'puppet-control-repo')
  $control_repo_path = "${work_dir}/${control_repo_name}"

  # Check if control repo exists
  $check_control_repo = run_command(
    "test -d ${control_repo_path} && echo 'exists' || echo 'not found'",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $check_control_repo.ok and $check_control_repo.first.value['stdout'].strip == 'exists' {
    $nessus_yaml_path = "${control_repo_path}/data/roles/role::pe::nessus.yaml"
    $use_control_repo = true
    out::message("  Updating control repo: ${nessus_yaml_path}...")

    # Ensure we're on production branch
    $checkout_prod = run_command(
      "cd ${control_repo_path} && git checkout production",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    unless $checkout_prod.ok {
      fail_plan("Failed to checkout production branch: ${checkout_prod.first.error}")
    }
  } else {
    $nessus_yaml_path = 'data/roles/role::pe::nessus.yaml'
    $use_control_repo = false
    out::message("  Updating proxtoboltfu: ${nessus_yaml_path}...")
  }

  # Write encrypted token to temp file to avoid shell escaping issues
  $temp_token_file = '/tmp/nessus_pe_token.tmp'

  $write_token = run_command(
    "echo '${encrypted_token}' > ${temp_token_file}",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $write_token.ok {
    fail_plan("Failed to write temp token file: ${write_token.first.error}")
  }

  # Use awk with -v to safely pass the token value
  # This handles both updating existing line and appending if not found
  $update_cmd = @("EOT")
    awk -v token="$(cat ${temp_token_file})" '
      BEGIN { found=0 }
      /^nessus_transformer::pe_token:/ { print "nessus_transformer::pe_token: " token; found=1; next }
      { print }
      END { if (!found) print "nessus_transformer::pe_token: " token }
    ' ${nessus_yaml_path} > ${nessus_yaml_path}.tmp && \
    mv ${nessus_yaml_path}.tmp ${nessus_yaml_path} && \
    rm ${temp_token_file}
    | EOT

  $update_result = run_command(
    $update_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $update_result.ok {
    fail_plan("Failed to update nessus.yaml: ${update_result.first.error}")
  }

  out::message("✓ Nessus Transformer PE token generated and stored successfully")
  out::message("  Token stored in: ${nessus_yaml_path} (eyaml encrypted)")

  # Commit and push changes if requested
  if $commit_changes {
    out::message("  Committing changes to git...")

    if $use_control_repo {
      # Working in control repo
      $git_commit = run_command(
        "cd ${control_repo_path} && git add \"data/roles/role::pe::nessus.yaml\" && git commit -m \"Update Nessus PE token\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\nCo-Authored-By: Claude <noreply@anthropic.com>\" && git push",
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      unless $git_commit.ok {
        fail_plan("Failed to commit changes: ${git_commit.first.error}")
      }

      out::message("  ✓ Changes committed and pushed to control repo")

      # Deploy via Code Manager
      out::message("  Deploying via Code Manager...")

      $code_deploy = run_command(
        'puppet-code deploy production --wait',
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      unless $code_deploy.ok {
        fail_plan("Failed to deploy code: ${code_deploy.first.error}")
      }

      out::message("  ✓ Code deployed via Code Manager")
    } else {
      # Working in proxtoboltfu
      $git_commit = run_command(
        "git add ${nessus_yaml_path} && git commit -m \"Update Nessus PE token\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\nCo-Authored-By: Claude <noreply@anthropic.com>\" && git push",
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      unless $git_commit.ok {
        fail_plan("Failed to commit changes: ${git_commit.first.error}")
      }

      out::message("  ✓ Changes committed and pushed to proxtoboltfu")
    }
  }

  return {
    status => 'completed',
    token_file => $nessus_yaml_path,
    committed => $commit_changes,
    control_repo => $use_control_repo
  }
}
