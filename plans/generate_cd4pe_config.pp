# @summary Generate CD4PE configuration in data/cd4pe.yaml
#
# Wrapper plan that calls cd4peadm::generate_config with the correct hiera_data_file_path
# to ensure CD4PE config is written to data/cd4pe.yaml instead of overwriting common.yaml.
#
# @param inventory_aio_target
#   The target to install CD4PE on
# @param resolvable_hostname
#   The hostname users will be able to access the CD4PE console at
# @param admin_password
#   Password for logging into the CD4PE Admin Console
# @param admin_username
#   The first CD4PE user (optional, defaults to 'admin')
# @param admin_db_password
#   Admin/superuser password for Postgres (optional, will be generated)
# @param cd4pe_db_password
#   Password for cd4pe database user (optional, will be generated)
# @param query_db_password
#   Password for query database user (optional, will be generated)
# @param secret_key
#   Encryption key for backend database secrets (optional, will be generated)
# @param runtime
#   Container runtime to use (optional, defaults to 'docker')
# @param optional_settings
#   Hash of optional settings (optional, defaults to {})
plan proxtoboltfu::generate_cd4pe_config (
  String $inventory_aio_target,
  String $resolvable_hostname,
  Sensitive[String] $admin_password,
  Optional[String] $admin_username = 'admin',
  Optional[Sensitive[String]] $admin_db_password = undef,
  Optional[Sensitive[String]] $cd4pe_db_password = undef,
  Optional[Sensitive[String]] $query_db_password = undef,
  Optional[Sensitive[String]] $secret_key = undef,
  Optional[String] $runtime = 'docker',
  Optional[Hash[String, Any]] $optional_settings = {},
) {

  out::message("Generating CD4PE configuration in data/cd4pe.yaml")

  # Build parameters hash
  $params = {
    'inventory_aio_target' => $inventory_aio_target,
    'resolvable_hostname' => $resolvable_hostname,
    'admin_password' => $admin_password,
    'admin_username' => $admin_username,
    'hiera_data_file_path' => 'data/cd4pe.yaml',
    'runtime' => $runtime,
    'optional_settings' => $optional_settings,
  }

  # Add optional parameters if provided
  $optional_params = {
    'admin_db_password' => $admin_db_password,
    'cd4pe_db_password' => $cd4pe_db_password,
    'query_db_password' => $query_db_password,
    'secret_key' => $secret_key,
  }.filter |$key, $value| { $value =~ NotUndef }

  $all_params = $params + $optional_params

  # Call the cd4peadm module's generate_config plan
  run_plan('cd4peadm::generate_config', $all_params)

  out::message("CD4PE configuration written to data/cd4pe.yaml")

  return { status => 'completed' }
}
