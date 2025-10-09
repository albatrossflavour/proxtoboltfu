# @summary Login to Puppet Enterprise console
plan proxtoboltfu::puppet_access_login {

  out::message("Logging in to Puppet Enterprise console")

  # Lookup console password and server name from hiera
  $params = lookup('peadm::config', Hash, first, undef)
  $console_password = $params['console_password']
  $pe_server = $params['primary_host']
  $token_file = "~/.puppetlabs/token-${pe_server}"

  # Run puppet access login locally with server-specific token file
  $result = run_command(
    "echo '${console_password}' | puppet access login --username admin --lifetime 10y --token-file ${token_file}",
    'localhost',
    '_run_as' => system::env('USER')
  )

  out::message("Logged in to Puppet Enterprise console")
  out::message("Token saved to ${token_file}")

  return { status => 'completed' }
}
