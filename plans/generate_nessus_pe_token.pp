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

  $encrypt_cmd = "echo '${pe_token}' | eyaml encrypt --stdin --pkcs7-private-key=keys/private_key.pkcs7.pem --pkcs7-public-key=keys/public_key.pkcs7.pem | grep 'ENC\\[' | sed 's/^string: //'"

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

  # Read current file to determine if we're adding or replacing
  $nessus_yaml_path = 'data/nessus.yaml'

  # Try to replace existing token value (could be ~ or an old encrypted value)
  $update_result = run_command(
    "sed -i.bak 's|^nessus_transformer::pe_token:.*|nessus_transformer::pe_token: ${encrypted_token}|' ${nessus_yaml_path} && rm ${nessus_yaml_path}.bak",
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
