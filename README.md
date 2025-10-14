# proxtoboltfu

## Puppet Infrastructure Automation

Automated provisioning and configuration of Puppet Enterprise
infrastructure on Proxmox using OpenTofu and Puppet Bolt.

## Overview

This project provides a complete infrastructure-as-code solution for deploying:

- **Puppet Enterprise** (PE) server
- **SCM/Comply** server for compliance management
- **CD4PE** server for continuous delivery
- **Dashboard** server for visualization
- **Nessus** vulnerability scanner
- **Puppet agent clients** across multiple OS distributions
- **Dynamic inventory** from Terraform state
- **Automatic DNS** registration via Pihole

The architecture separates infrastructure provisioning (OpenTofu)
from configuration management (Bolt) for clean, repeatable
deployments.

## Prerequisites

### Required Tools

- OpenTofu >= 1.10.0 (or Terraform)
- [Puppet Bolt][bolt-install] >= 3.0
- Puppet Enterprise installer (downloaded separately)
- Git for version control

[bolt-install]: https://help.puppet.com/bolt/current/topics/bolt_installing.htm

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
- **SSH access** to Proxmox hosts

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
eyaml createkeys \
  --pkcs7-private-key=keys/private_key.pkcs7.pem \
  --pkcs7-public-key=keys/public_key.pkcs7.pem
chmod 600 keys/private_key.pkcs7.pem
chmod 644 keys/public_key.pkcs7.pem
```

**Important:** Keep `private_key.pkcs7.pem` secure.
Never commit it to version control.

### 3. Configure Terraform Variables

Create `tf/terraform.tfvars` with your environment-specific values:

```hcl
# Proxmox Configuration
api_url = "https://proxmox.yourdomain.com:8006/api2/json"
proxmox_token_id = "terraform@pam!terraform"
proxmox_token_secret = "your-proxmox-token-secret"

# Infrastructure Toggles
puppet_pe        = true   # Deploy Puppet Enterprise
puppet_scm       = true   # Deploy SCM/Comply
puppet_cd4pe     = true   # Deploy CD4PE
puppet_dashboard = true   # Deploy Dashboard
nessus           = true   # Deploy Nessus

# OS Distribution Controls
enable_alma        = false
enable_centos      = false
enable_debian      = false
enable_oracle      = false
enable_redhat      = false
enable_rocky       = false
enable_ubuntu      = true
enable_opensuse    = false
enable_amazonlinux = false

# Client Counts
prod_clients = 1  # Number of clients per OS in production
dev_clients  = 0  # Number of clients per OS in development

# VM Defaults
ciuser = "yourusername"
cipassword = "your-cloud-init-password"
sshkey = "ssh-ed25519 AAAAC3... your-public-key"

# Pihole Configuration
pihole_password = "your-pihole-admin-password"
domain          = "yourdomain.com"

# PE Console
console_password = "your-pe-console-password"

# Optional: Customize defaults
storage_location = "ceph"
disk_size = "37G"
cores = 2
memory = 1536
```

**Security Note:** This file contains secrets.
Add to `.gitignore`:

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
    # Encrypt with: eyaml encrypt -s 'password'
    ENC[PKCS7,...]
  version: "2023.8.0"
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
    # Update if using different key
    private-key: ~/.ssh/id_ed25519
    # Match ciuser from terraform.tfvars
    user: yourusername
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

### Full Stack Deployment (Single Command)

```bash
bolt plan run proxtoboltfu::build_environment
```

This orchestrates the complete deployment:

1. Provisions infrastructure with OpenTofu (VMs + DNS)
2. Builds Puppet Enterprise server
3. Builds additional infrastructure (SCM, CD4PE, Dashboard,
   Nessus) in parallel
4. Builds agent nodes if any exist

**Expected time:** 30-45 minutes

To skip infrastructure provisioning (if VMs already exist):

```bash
bolt plan run proxtoboltfu::build_environment \
  apply_terraform=false
```

### Manual Step-by-Step Deployment

If you prefer manual control:

#### 1. Provision Infrastructure

```bash
cd tf
tofu init
tofu plan   # Review what will be created
tofu apply
cd ..
```

This creates VMs and DNS records for enabled infrastructure.

**Expected time:** 2-3 minutes

#### 2. Build Puppet Enterprise

```bash
bolt plan run proxtoboltfu::build_pe
```

This installs and configures PE, deploys code, and installs
eyaml keys.

**Expected time:** 20-30 minutes

#### 3. Build Additional Infrastructure

These can run in parallel:

```bash
bolt plan run proxtoboltfu::build_scm
bolt plan run proxtoboltfu::build_cd4pe
bolt plan run proxtoboltfu::build_dashboard
bolt plan run proxtoboltfu::build_nessus
```

**Expected time:** 15-20 minutes each

#### 4. Build Agent Nodes

```bash
bolt plan run proxtoboltfu::build_agents
```

**Expected time:** Varies by agent count
(1-2 minutes per agent)

### Managing Agent Clients

**Deploy Clients:**

1. Configure client counts in `tf/terraform.tfvars`
2. Apply infrastructure: `cd tf && tofu apply && cd ..`
3. Configure agents: `bolt plan run proxtoboltfu::build_agents`

**Destroy Clients:**

```bash
# Preview what will be destroyed
bolt plan run proxtoboltfu::destroy_clients

# Actually destroy (purges from PE, then destroys VMs)
bolt plan run proxtoboltfu::destroy_clients confirm=true
```

The destroy process automatically purges agent certificates from
Puppet Enterprise before destroying VMs.

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

<!-- markdownlint-disable MD013 -->

| Variable               | Required | Default                | Description              |
| ---------------------- | -------- | ---------------------- | ------------------------ |
| `api_url`              | Yes      | -                      | Proxmox API URL          |
| `proxmox_token_id`     | Yes      | -                      | Proxmox API token ID     |
| `proxmox_token_secret` | Yes      | -                      | Proxmox token secret     |
| `puppet_pe`            | No       | false                  | Deploy Puppet Enterprise |
| `puppet_scm`           | No       | false                  | Deploy SCM/Comply        |
| `puppet_cd4pe`         | No       | false                  | Deploy CD4PE             |
| `puppet_dashboard`     | No       | false                  | Deploy Dashboard         |
| `nessus`               | No       | false                  | Deploy Nessus            |
| `enable_alma`          | No       | false                  | Enable Alma Linux        |
| `enable_centos`        | No       | false                  | Enable CentOS            |
| `enable_debian`        | No       | false                  | Enable Debian            |
| `enable_oracle`        | No       | false                  | Enable Oracle Linux      |
| `enable_redhat`        | No       | false                  | Enable RHEL              |
| `enable_rocky`         | No       | false                  | Enable Rocky Linux       |
| `enable_ubuntu`        | No       | false                  | Enable Ubuntu            |
| `enable_opensuse`      | No       | false                  | Enable OpenSUSE          |
| `enable_amazonlinux`   | No       | false                  | Enable Amazon Linux      |
| `prod_clients`         | No       | 0                      | Clients per OS (prod)    |
| `dev_clients`          | No       | 0                      | Clients per OS (dev)     |
| `ciuser`               | Yes      | -                      | Cloud-init user          |
| `cipassword`           | Yes      | -                      | Cloud-init password      |
| `sshkey`               | Yes      | -                      | SSH public key           |
| `pihole_password`      | Yes      | -                      | Pihole admin password    |
| `domain`               | No       | `albatrossflavour.com` | Base domain              |
| `console_password`     | Yes      | -                      | PE console password      |
| `storage_location`     | No       | `ceph`                 | Proxmox storage pool     |
| `disk_size`            | No       | `37G`                  | VM disk size             |
| `cores`                | No       | 2                      | VM CPU cores             |
| `memory`               | No       | 1536                   | VM RAM (MB)              |

<!-- markdownlint-enable MD013 -->

### Hiera Configuration Keys

**Required in `data/common.yaml`:**

```yaml
peadm::config:
  # PE server hostname
  primary_host: <fqdn>
  # PE console admin password
  console_password: <encrypted>
  # PE version to install
  version: <version>

complyadm::config:
  # SCM server hostname
  resolvable_hostname: <fqdn>

cd4peadm::config:
  # CD4PE server hostname
  resolvable_hostname: <fqdn>
```

See module documentation for additional configuration options:

- [peadm](https://forge.puppet.com/modules/puppetlabs/peadm)
- [cd4peadm](https://forge.puppet.com/modules/puppetlabs/cd4peadm)
- [complyadm](https://forge.puppet.com/modules/puppetlabs/complyadm)

### VM Specifications

| Server     | VMID       | vCPU     | RAM   | Disk  | OS           |
| ---------- | ---------- | -------- | ----- | ----- | ------------ |
| PE Primary | 999        | 12 (3x4) | 16GB  | 100GB | Ubuntu 24.04 |
| SCM        | 998        | 8 (2x4)  | 8GB   | 50GB  | Ubuntu 22.04 |
| CD4PE      | 997        | 8 (2x4)  | 8GB   | 50GB  | Ubuntu 24.04 |
| Dashboard  | 996        | 4 (2x2)  | 4GB   | 50GB  | Ubuntu 22.04 |
| Nessus     | 995        | 4 (2x2)  | 4GB   | 50GB  | Ubuntu 22.04 |
| Agents     | 1xxx-9xxxx | 2 (1x2)  | 1.5GB | 37GB  | Varies       |

Agent VMs are created dynamically based on enabled OS
distributions and client counts.

### Tags

Infrastructure uses tags for dynamic inventory grouping:

| Tag            | Purpose            | Example Use       |
| -------------- | ------------------ | ----------------- |
| `puppetinfra`  | All infrastructure | Broad maintenance |
| `puppet`       | PE servers         | PE operations     |
| `scm`          | SCM servers        | Compliance        |
| `cd4pe`        | CD4PE servers      | Pipeline mgmt     |
| `dashboard`    | Dashboard servers  | Visualization     |
| `nessus`       | Nessus scanners    | Security scan     |
| `puppetagents` | Agent nodes        | Agent deploy      |

Add new tags by editing `tags` in Terraform resources, then
create inventory groups in `inventory.yaml`.

## Management Tasks

### Add Agent Nodes

Agent nodes are managed via `tf/clients.tf` which uses dynamic
configuration:

1. **Enable OS distributions** in `tf/terraform.tfvars`:

   ```hcl
   enable_ubuntu = true
   enable_rocky  = true
   prod_clients  = 2
   dev_clients   = 1
   ```

2. **Apply Terraform:**

   ```bash
   cd tf && tofu apply
   ```

3. **Deploy agents:**

   ```bash
   bolt plan run proxtoboltfu::build_agents
   ```

This creates agents for each enabled OS version in both
environments. For example, with the above config:

- Ubuntu: 20.04, 22.04, 24.04 (3 versions × 3 clients =
  9 agents)
- Rocky: 8, 9 (2 versions × 3 clients = 6 agents)
- **Total: 15 agents**

### Destroy Infrastructure

**Destroy Agent Clients Only:**

```bash
# Preview what will be destroyed
bolt plan run proxtoboltfu::destroy_clients

# Confirm and destroy
bolt plan run proxtoboltfu::destroy_clients confirm=true
```

This automatically purges certificates from PE before destroying VMs.

**Destroy All Infrastructure:**

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
PT_dir=tf PT_tag_filter=puppet \
  ./tasks/tofu_inventory.sh
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
ssh -i ~/.ssh/id_ed25519 \
  yourusername@192.168.7.100

# Check inventory configuration
bolt inventory show --detail \
  --targets new-puppet.yourdomain.com
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

See [CLAUDE.md](CLAUDE.md) for detailed architecture
documentation, including:

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

- **Proxmox:** See [Proxmox VE Documentation][proxmox-docs]
- **Puppet Enterprise:** See [PE Documentation][pe-docs]
- **Bolt:** See [Bolt Documentation][bolt-docs]
- **This Project:** See [CLAUDE.md](CLAUDE.md) or open an issue

[proxmox-docs]: https://pve.proxmox.com/pve-docs/
[pe-docs]: https://puppet.com/docs/pe/
[bolt-docs]: https://puppet.com/docs/bolt/
