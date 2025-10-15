# @summary Generate PE RBAC token for Nessus Transformer
# @param regenerate Whether to regenerate token even if one exists (default: false)
plan proxtoboltfu::generate_nessus_pe_token (
  Boolean $regenerate = false
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

  # Update data/nessus.yaml with encrypted token
  out::message("  Updating data/nessus.yaml...")

  # Use a more robust method to update the file
  # Write encrypted token to temp file to avoid shell escaping issues
  $nessus_yaml_path = 'data/nessus.yaml'
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
  $update_cmd = @("EOT")
    awk -v token="$(cat ${temp_token_file})" '/^nessus_transformer::pe_token:/ { print "nessus_transformer::pe_token: " token; next } {print}' ${nessus_yaml_path} > ${nessus_yaml_path}.tmp && \
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
  out::message("  Token stored in: data/nessus.yaml (eyaml encrypted)")

  return {
    status => 'completed',
    token_file => $nessus_yaml_path
  }
}
