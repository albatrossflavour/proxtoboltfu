# proxtoboltfu - Puppet Infrastructure Automation

Automated provisioning and configuration of Puppet Enterprise infrastructure on Proxmox using OpenTofu and Puppet Bolt.

## Overview

This project provides a complete infrastructure-as-code solution for deploying:
- **Puppet Enterprise** (PE) server
- **SCM/Comply** server for compliance management
- **CD4PE** server for continuous delivery
- **Dynamic inventory** from Terraform state
- **Automatic DNS** registration via Pihole

The architecture separates infrastructure provisioning (OpenTofu) from configuration management (Bolt) for clean, repeatable deployments.

## Prerequisites

### Required Tools

- **OpenTofu** >= 1.10.0 (or Terraform)
- **Puppet Bolt** >= 3.0
- **Puppet Enterprise** installer (downloaded separately)
- **eyaml** gem for encrypted hiera data
- **Git** for version control

Install tools:
```bash
# macOS with Homebrew
brew install opentofu puppet-bolt

# Install eyaml
gem install hiera-eyaml
```

### Required Infrastructure

- **Proxmox VE** cluster with API access
- **Pihole** DNS server with API access
- **VM templates** in Proxmox:
  - `template-Ubuntu-2404` (for PE server)
  - `template-Ubuntu-2204` (for SCM/CD4PE)
- **Network** with VLAN 7, gateway 192.168.7.1
- **IP range** available: 192.168.7.100-102 (expandable)
- **SSH access** to Proxmox hosts
- **ed25519 SSH key** at `~/.ssh/id_ed25519`

### Required Access

- Proxmox API token with appropriate permissions
- Pihole admin password
- Puppet Enterprise license key (for production deployments)

## Initial Setup

### 1. Clone and Configure Repository

```bash
git clone <repository-url> proxtoboltfu
cd proxtoboltfu
```

### 2. Generate Eyaml Keys

Create encryption keys for sensitive hiera data:

```bash
mkdir -p keys
eyaml createkeys --pkcs7-private-key=keys/private_key.pkcs7.pem \
                 --pkcs7-public-key=keys/public_key.pkcs7.pem
chmod 600 keys/private_key.pkcs7.pem
chmod 644 keys/public_key.pkcs7.pem
```

**Important:** Keep `private_key.pkcs7.pem` secure. Never commit it to version control.

### 3. Configure Terraform Variables

Create `tf/terraform.tfvars` with your environment-specific values:

```hcl
# Proxmox Configuration
api_url              = "https://proxmox.yourdomain.com:8006/api2/json"
proxmox_token_id     = "terraform@pam!terraform"
proxmox_token_secret = "your-proxmox-token-secret"

# Infrastructure Toggles
puppet_pe    = true   # Deploy Puppet Enterprise
puppet_scm   = true   # Deploy SCM/Comply
puppet_cd4pe = true   # Deploy CD4PE

# VM Defaults
ciuser     = "yourusername"
cipassword = "your-cloud-init-password"
sshkey     = "ssh-ed25519 AAAAC3... your-public-key"

# Pihole Configuration
pihole_password = "your-pihole-admin-password"
domain          = "yourdomain.com"

# PE Console
console_password = "your-pe-console-password"

# Optional: Customize defaults
storage_location = "ceph"
disk_size       = "37G"
cores           = 2
memory          = 1536
```

**Security Note:** This file contains secrets. Add to `.gitignore`:
```bash
echo "tf/terraform.tfvars" >> .gitignore
```

### 4. Configure Hiera Data

Edit `data/common.yaml` with your infrastructure details:

```yaml
---
# Puppet Enterprise Configuration
peadm::config:
  primary_host: new-puppet.yourdomain.com
  console_password: >
    ENC[PKCS7,...]  # Encrypt with: eyaml encrypt -s 'password'
  version: '2023.8.0'
  # ... additional PE config

# SCM Configuration
complyadm::config:
  resolvable_hostname: new-scm.yourdomain.com
  # ... additional SCM config

complyadm::csr_attributes:
  datacenter: lab
  role: role::pe::scm
  environment: production

# CD4PE Configuration
cd4peadm::config:
  resolvable_hostname: new-cd4pe.yourdomain.com
  # ... additional CD4PE config

cd4peadm::csr_attributes:
  datacenter: lab
  role: role::pe::cd4pe
  environment: production
```

**Encrypt Sensitive Values:**
```bash
eyaml encrypt -s 'your-sensitive-value' \
  --pkcs7-private-key=keys/private_key.pkcs7.pem \
  --pkcs7-public-key=keys/public_key.pkcs7.pem
```

Copy the output (including `ENC[PKCS7,...]`) into your hiera data.

### 5. Update Inventory Configuration

Edit `inventory.yaml` if needed (defaults should work):

```yaml
---
version: 2
config:
  transport: ssh
  ssh:
    private-key: ~/.ssh/id_ed25519  # Update if using different key
    user: yourusername               # Match ciuser from terraform.tfvars
    run-as: root
    host-key-check: false
    tmpdir: /var/tmp
# ... groups are auto-populated from Terraform state
```

### 6. Configure Bolt Project

Review `bolt-project.yaml` and update module dependencies if needed:

```yaml
name: proxtoboltfu
modules:
  - name: puppetlabs-peadm
  - name: puppetlabs-cd4peadm
  - name: puppetlabs-complyadm
# Install dependencies:
```

```bash
bolt module install
```

## Deployment

### Full Stack Deployment

Deploy the complete Puppet infrastructure in order:

#### 1. Provision Infrastructure

```bash
cd tf
tofu init
tofu plan   # Review what will be created
tofu apply
```

This creates:
- Puppet Enterprise VM (new-puppet.yourdomain.com, 192.168.7.100)
- SCM VM (new-scm.yourdomain.com, 192.168.7.101)
- CD4PE VM (new-cd4pe.yourdomain.com, 192.168.7.102)
- DNS records in Pihole

**Expected time:** 2-3 minutes

#### 2. Verify Infrastructure

```bash
# Return to project root
cd ..

# Check inventory discovered VMs
bolt inventory show --targets puppet-infrastructure

# Test connectivity
bolt command run 'hostname' --targets puppet-infrastructure
```

Expected output: All three hosts respond with their hostnames.

#### 3. Build Puppet Enterprise

```bash
bolt plan run proxtoboltfu::build_pe
```

This:
- Installs Puppet Enterprise
- Configures primary server
- Deploys code to environments
- Installs eyaml keys

**Expected time:** 20-30 minutes

#### 4. Build SCM and CD4PE

These can run in parallel or sequentially:

```bash
# Option 1: Run sequentially
bolt plan run proxtoboltfu::build_scm
bolt plan run proxtoboltfu::build_cd4pe

# Option 2: Run in parallel (separate terminals)
bolt plan run proxtoboltfu::build_scm &
bolt plan run proxtoboltfu::build_cd4pe &
wait
```

**Expected time:** 15-20 minutes each

#### 5. Post-Installation

```bash
# Download CA certificate from PE server
bolt plan run proxtoboltfu::fetch_ca_cert

# Login to PE console
bolt plan run proxtoboltfu::puppet_access_login \
  console_password='your-console-password'
```

### Verification

```bash
# Check all infrastructure
bolt inventory show --detail

# Verify PE is running
bolt command run 'systemctl status pe-puppetserver' \
  --targets puppet-enterprise-nodes

# Access PE Console
open https://new-puppet.yourdomain.com
```

## Configuration Reference

### Terraform Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `api_url` | Yes | - | Proxmox API URL |
| `proxmox_token_id` | Yes | - | Proxmox API token ID |
| `proxmox_token_secret` | Yes | - | Proxmox API token secret |
| `puppet_pe` | No | false | Deploy Puppet Enterprise |
| `puppet_scm` | No | false | Deploy SCM/Comply |
| `puppet_cd4pe` | No | false | Deploy CD4PE |
| `ciuser` | Yes | - | Cloud-init default user |
| `cipassword` | Yes | - | Cloud-init default password |
| `sshkey` | Yes | - | SSH public key for access |
| `pihole_password` | Yes | - | Pihole admin password |
| `domain` | No | `albatrossflavour.com` | Base domain |
| `console_password` | Yes | - | PE console admin password |
| `storage_location` | No | `ceph` | Proxmox storage pool |
| `disk_size` | No | `37G` | VM disk size |
| `cores` | No | 2 | VM CPU cores |
| `memory` | No | 1536 | VM RAM (MB) |

### Hiera Configuration Keys

**Required in `data/common.yaml`:**

```yaml
peadm::config:
  primary_host: <fqdn>          # PE server hostname
  console_password: <encrypted> # PE console admin password
  version: <version>            # PE version to install

complyadm::config:
  resolvable_hostname: <fqdn>   # SCM server hostname

cd4peadm::config:
  resolvable_hostname: <fqdn>   # CD4PE server hostname
```

See module documentation for additional configuration options:
- [peadm](https://forge.puppet.com/modules/puppetlabs/peadm)
- [cd4peadm](https://forge.puppet.com/modules/puppetlabs/cd4peadm)
- [complyadm](https://forge.puppet.com/modules/puppetlabs/complyadm)

### VM Specifications

| Server | VMID | IP | vCPU | RAM | Disk | OS |
|--------|------|-------|------|-----|------|-----|
| PE Primary | 999 | 192.168.7.100 | 12 (3x4) | 16GB | 100GB | Ubuntu 24.04 |
| SCM | 998 | 192.168.7.101 | 8 (2x4) | 8GB | 50GB | Ubuntu 22.04 |
| CD4PE | 997 | 192.168.7.102 | 8 (2x4) | 8GB | 50GB | Ubuntu 24.04 |

### Tags

Infrastructure uses tags for dynamic inventory grouping:

| Tag | Purpose | Example Use |
|-----|---------|-------------|
| `puppetinfra` | All infrastructure | Broad maintenance tasks |
| `puppet` | PE servers | PE-specific operations |
| `scm` | SCM servers | Compliance tasks |
| `cd4pe` | CD4PE servers | Pipeline management |
| `puppetagents` | Agent nodes | Agent deployment |
| `prod` | Production | Environment filtering |
| `ubuntu` | OS type | OS-specific tasks |

Add new tags by editing `tags` in Terraform resources, then create inventory groups.

## Management Tasks

### Add Agent Nodes

1. **Create Terraform resource** in `tf/agents.tf`:
   ```hcl
   resource "proxmox_vm_qemu" "puppet-agent" {
     count = var.prod_clients
     tags  = "puppetagents;prod;ubuntu"
     # ... configuration
   }
   ```

2. **Apply Terraform:**
   ```bash
   cd tf && tofu apply
   ```

3. **Verify inventory:**
   ```bash
   bolt inventory show --targets puppet-agents
   ```

4. **Install agents:**
   ```bash
   bolt plan run <your-agent-install-plan> --targets puppet-agents
   ```

### Destroy Infrastructure

**Warning:** This destroys all VMs and data.

```bash
cd tf
tofu destroy
```

Review the plan carefully before confirming.

### Update Infrastructure

Modify Terraform files, then:

```bash
cd tf
tofu plan   # Review changes
tofu apply
```

Re-run Bolt plans if configuration changed:
```bash
bolt plan run proxtoboltfu::build_pe
```

### Troubleshooting

**Inventory not showing targets:**
```bash
# Test inventory task directly
PT_dir=tf ./tasks/tofu_inventory.sh

# Check specific tag filter
PT_dir=tf PT_tag_filter=puppet ./tasks/tofu_inventory.sh
```

**DNS not resolving:**
```bash
# Test DNS resolution
dig new-puppet.yourdomain.com

# Check Pihole
curl -X GET "http://pihole.yourdomain.com/api/dns"
```

**Plans fail with connection errors:**
```bash
# Test SSH manually
ssh -i ~/.ssh/id_ed25519 yourusername@192.168.7.100

# Check inventory configuration
bolt inventory show --detail --targets new-puppet.yourdomain.com
```

**Eyaml decryption fails:**
```bash
# Verify keys exist and have correct permissions
ls -la keys/
# private_key.pkcs7.pem should be 600
# public_key.pkcs7.pem should be 644

# Test decryption
eyaml decrypt -f data/common.yaml
```

## Architecture

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation, including:
- Design decisions and rationale
- Tag-based inventory system
- Dynamic inventory implementation
- Separation of Terraform and Bolt
- Troubleshooting guide

## Security Considerations

### Sensitive Data

**Never commit:**
- `tf/terraform.tfvars` (contains secrets)
- `keys/private_key.pkcs7.pem` (eyaml private key)
- Any files with unencrypted passwords

**Always encrypt in hiera:**
- Passwords
- API tokens
- License keys
- Private keys

**Use appropriate permissions:**
```bash
chmod 600 keys/private_key.pkcs7.pem
chmod 600 tf/terraform.tfvars
```

### Network Security

- Infrastructure deployed on private VLAN (7)
- SSH key-based authentication only
- Consider firewall rules for production
- Rotate API tokens regularly

### Access Control

- Proxmox: Use dedicated service account with minimal permissions
- Pihole: Use strong admin password, consider HTTPS
- Puppet: Follow PE security best practices
- SSH: Disable password authentication, use ed25519 keys

## Contributing

This is a personal infrastructure project. If adapting for your use:

1. Fork the repository
2. Update all hostnames, IPs, and domains
3. Generate your own eyaml keys
4. Customize VM specifications as needed
5. Review and update all hiera configuration

## License

[Add your license here]

## Support

For issues specific to:
- **Proxmox:** See [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- **Puppet Enterprise:** See [PE Documentation](https://puppet.com/docs/pe/)
- **Bolt:** See [Bolt Documentation](https://puppet.com/docs/bolt/)
- **This Project:** See [CLAUDE.md](CLAUDE.md) or open an issue
