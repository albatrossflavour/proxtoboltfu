# @summary Download CA certificate from new PE server
plan proxtoboltfu::fetch_ca_cert {

  # Lookup PE config from hiera
  $peadm_config = lookup('peadm::config', Hash, first, undef)
  $pe_server = $peadm_config['primary_host']

  $targets = get_targets($pe_server)

  out::message("Downloading CA certificate from ${pe_server}")

  # Download CA cert from new PE server
  download_file(
    '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
    "~/.puppetlabs/etc/puppet/ssl/${pe_server}.pem",
    $targets
  )

  out::message("CA certificate downloaded successfully to ~/.puppetlabs/etc/puppet/ssl/${pe_server}.pem")

  return { status => 'completed' }
}
