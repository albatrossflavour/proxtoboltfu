# @summary Generate SCM/Comply configuration in data/scm.yaml
#
# Wrapper plan that calls complyadm::generate_config with the correct hiera_data_file_path
# to ensure SCM config is written to data/scm.yaml instead of overwriting common.yaml.
#
# @param inventory_aio_target
#   The target to install Comply on
# @param resolvable_hostname
#   The hostname users will be able to access the Comply console at
# @param pe_target
#   The Puppet Enterprise server (optional, defaults to empty string)
# @param admin_db_password
#   Admin/superuser password for Postgres (optional, will be generated)
# @param comply_db_password
#   Password for comply database user (optional, will be generated)
# @param identity_db_password
#   Password for identity database user (optional, will be generated)
# @param secret_key
#   Encryption key for backend database secrets (optional, will be generated)
# @param cookie_secret
#   Cookie secret (optional, will be generated)
# @param db_encryption_key
#   Database encryption key (optional, will be generated)
# @param hasura_admin_secret
#   Hasura admin secret (optional, will be generated)
# @param redis_password
#   Redis password (optional, will be generated)
# @param client_secret
#   Client secret (optional, will be generated)
# @param identity_admin_password
#   Identity admin password (optional, will be generated)
# @param runtime
#   Container runtime to use (optional, defaults to 'docker')
plan proxtoboltfu::generate_scm_config (
  String $inventory_aio_target,
  String $resolvable_hostname,
  Optional[String] $pe_target = '',
  Optional[Sensitive[String]] $admin_db_password = undef,
  Optional[Sensitive[String]] $comply_db_password = undef,
  Optional[Sensitive[String]] $identity_db_password = undef,
  Optional[Sensitive[String]] $secret_key = undef,
  Optional[Sensitive[String]] $cookie_secret = undef,
  Optional[Sensitive[String]] $db_encryption_key = undef,
  Optional[Sensitive[String]] $hasura_admin_secret = undef,
  Optional[Sensitive[String]] $redis_password = undef,
  Optional[Sensitive[String]] $client_secret = undef,
  Optional[Sensitive[String]] $identity_admin_password = undef,
  Optional[String] $runtime = 'docker',
) {

  out::message("Generating SCM/Comply configuration in data/scm.yaml")

  # Build parameters hash, only including non-undef values
  $params = {
    'inventory_aio_target' => $inventory_aio_target,
    'resolvable_hostname' => $resolvable_hostname,
    'pe_target' => $pe_target,
    'hiera_data_file_path' => 'data/scm.yaml',
    'runtime' => $runtime,
  }

  # Add optional parameters if provided
  $optional_params = {
    'admin_db_password' => $admin_db_password,
    'comply_db_password' => $comply_db_password,
    'identity_db_password' => $identity_db_password,
    'secret_key' => $secret_key,
    'cookie_secret' => $cookie_secret,
    'db_encryption_key' => $db_encryption_key,
    'hasura_admin_secret' => $hasura_admin_secret,
    'redis_password' => $redis_password,
    'client_secret' => $client_secret,
    'identity_admin_password' => $identity_admin_password,
  }.filter |$key, $value| { $value =~ NotUndef }

  $all_params = $params + $optional_params

  # Call the complyadm module's generate_config plan
  run_plan('complyadm::generate_config', $all_params)

  out::message("SCM configuration written to data/scm.yaml")

  return { status => 'completed' }
}
