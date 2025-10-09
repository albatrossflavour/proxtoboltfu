# @summary Login to Puppet Enterprise console
plan proxtoboltfu::puppet_access_login {

  out::message("Logging in to Puppet Enterprise console")

  # Lookup console password from hiera
  $params = lookup('peadm::config', Hash, first, undef)
  $console_password = $params['console_password']

  # Run puppet access login locally
  $result = run_command(
    "echo '${console_password}' | puppet access login --username admin --lifetime 10y",
    'localhost',
    '_run_as' => system::env('USER')
  )

  out::message("Logged in to Puppet Enterprise console")

  return { status => 'completed' }
}
