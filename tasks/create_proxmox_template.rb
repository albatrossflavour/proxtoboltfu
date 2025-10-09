#!/opt/puppetlabs/puppet/bin/ruby
# Create Proxmox VM template with KFVEE numbering

require 'json'
require 'open3'
require 'uri'
require 'net/http'

def calculate_kfvee_id(os_name, os_version, environment = 'prod', instance = 1)
  # KFVEE numbering system implementation
  kernel = 1  # Linux = 1, Windows = 2

  # OS Family mapping
  family = case os_name.downcase
  when /alma|rocky|centos|oracle|rhel|redhat/
    1  # RedHat family
  when /debian|ubuntu/
    2  # Debian family
  when /opensuse|sles/
    3  # SUSE family
  when /amazon/
    5  # Amazon family
  when /fedora/
    6  # Fedora family
  else
    1  # Default to RedHat
  end

  # Version digit (use major version)
  version_digit = os_version.to_i % 10

  # Environment + Instance (0X = prod, 1X = dev)
  env_base = environment == 'prod' ? 0 : 10
  env_instance = env_base + instance.to_i

  # Build 5-digit VMID
  vmid = "#{kernel}#{family}#{version_digit}#{'%02d' % env_instance}".to_i

  return vmid
end

def download_iso(url, filename, iso_dir)
  iso_path = File.join(iso_dir, filename)

  # Skip if file already exists
  return iso_path if File.exist?(iso_path)

  # Download the ISO
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new(uri)

    File.open("#{iso_path}.tmp", 'wb') do |file|
      http.request(request) do |response|
        response.read_body do |chunk|
          file.write(chunk)
        end
      end
    end
  end

  # Move temp file to final location
  File.rename("#{iso_path}.tmp", iso_path)
  iso_path
end

def main
  params = JSON.parse(STDIN.read)

  template_name = params['template_name']
  template_version = params['template_version']
  iso_url = params['iso_url']
  iso_filename = params['iso_filename']
  vmid = params['vmid'] || calculate_kfvee_id(template_name, template_version)
  storage_location = params['storage_location'] || 'ceph'
  force_rebuild = params['force_rebuild'] || false

  iso_dir = '/mnt/pve/luggage/template/iso'

  # Check if template already exists
  unless force_rebuild
    check_cmd = ['qm', 'list', '--full']
    stdout, stderr, status = Open3.capture3(*check_cmd)

    if status.success? && stdout.include?(vmid.to_s)
      return {
        'status' => 'skipped',
        'vmid' => vmid,
        'message' => "Template #{template_name} #{template_version} (#{vmid}) already exists"
      }
    end
  end

  # Download ISO if needed
  begin
    iso_path = download_iso(iso_url, iso_filename, iso_dir)
  rescue => e
    return {
      'status' => 'error',
      'error' => "Failed to download ISO: #{e.message}"
    }
  end

  # Create VM with cloud-init
  create_cmd = [
    'qm', 'create', vmid.to_s,
    '--name', "#{template_name.downcase}-#{template_version}",
    '--memory', '2048',
    '--cores', '2',
    '--net0', 'virtio,bridge=vmbr1,tag=7',
    '--scsihw', 'virtio-scsi-pci',
    '--scsi0', "#{storage_location}:32,format=qcow2",
    '--ide2', "#{storage_location}:cloudinit",
    '--boot', 'c',
    '--bootdisk', 'scsi0',
    '--agent', 'enabled=1',
    '--cdrom', iso_path
  ]

  stdout, stderr, status = Open3.capture3(*create_cmd)

  unless status.success?
    return {
      'status' => 'error',
      'error' => "Failed to create VM: #{stderr}",
      'vmid' => vmid
    }
  end

  # Start VM for installation (would need actual installation automation here)
  # This is simplified - in practice you'd need preseed/kickstart automation

  # Convert to template
  template_cmd = ['qm', 'template', vmid.to_s]
  stdout, stderr, status = Open3.capture3(*template_cmd)

  if status.success?
    {
      'status' => 'success',
      'vmid' => vmid,
      'template_name' => "#{template_name.downcase}-#{template_version}",
      'message' => "Successfully created template #{template_name} #{template_version}"
    }
  else
    {
      'status' => 'error',
      'error' => "Failed to convert to template: #{stderr}",
      'vmid' => vmid
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
