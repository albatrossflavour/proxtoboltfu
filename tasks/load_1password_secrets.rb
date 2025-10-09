#!/opt/puppetlabs/puppet/bin/ruby
# Load secrets from 1Password CLI for Terraform operations

require 'json'
require 'open3'

def main
  # Define the secrets we need from 1Password
  secret_mappings = {
    'TF_VAR_proxmox_password' => 'op://proxtoboltfu/proxmox-credentials/password',
    'TF_VAR_pe_console_password' => 'op://proxtoboltfu/pe-credentials/console_password',
    'TF_VAR_sudo_password' => 'op://proxtoboltfu/pe-credentials/sudo_password',
    'TF_VAR_windows_password' => 'op://proxtoboltfu/pe-credentials/windows_password',
    'TF_VAR_forge_token' => 'op://proxtoboltfu/pe-credentials/forge_token',
    'AWS_ACCESS_KEY_ID' => 'op://proxtoboltfu/aws-s3-backend/access_key_id',
    'AWS_SECRET_ACCESS_KEY' => 'op://proxtoboltfu/aws-s3-backend/secret_access_key'
  }

  secrets = {}
  errors = []

  # Load each secret from 1Password
  secret_mappings.each do |env_var, op_path|
    stdout, stderr, status = Open3.capture3('op', 'read', op_path)

    if status.success?
      secrets[env_var] = stdout.strip
    else
      errors << "Failed to load #{env_var}: #{stderr.strip}"
    end
  end

  if errors.empty?
    {
      'status' => 'success',
      'secrets' => secrets
    }
  else
    {
      'status' => 'error',
      'errors' => errors,
      'error' => "Failed to load some secrets from 1Password: #{errors.join(', ')}"
    }
  end

rescue => e
  {
    'status' => 'error',
    'error' => e.message,
    'backtrace' => e.backtrace
  }
end

puts main.to_json
