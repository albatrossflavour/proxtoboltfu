# proxtoboltfu Project Structure

## Overview

This project uses OpenTofu (Terraform) to provision Proxmox VMs, Pihole for DNS management, and Puppet Bolt to configure infrastructure. The design separates infrastructure provisioning from configuration management for clean, predictable deployments.

## Directory Structure

```text
proxtoboltfu/
├── tf/                           # OpenTofu/Terraform configuration
│   ├── puppet.tf                 # Puppet Enterprise server (VMID 999, IP .100)
│   ├── scm.tf                    # SCM/Comply server (VMID 998, IP .101)
│   ├── cd4pe.tf                  # CD4PE server (VMID 997, IP .102)
│   ├── provider.tf               # Proxmox and Pihole providers
│   └── variables.tf              # Variable definitions
├── plans/                        # Puppet Bolt plans
│   ├── build_pe.pp               # Build Puppet Enterprise server
│   ├── build_scm.pp              # Build SCM server
│   ├── build_cd4pe.pp            # Build CD4PE server
│   ├── fetch_ca_cert.pp          # Download CA cert from PE server
│   └── puppet_access_login.pp    # Login to PE console
├── tasks/                        # Bolt tasks
│   ├── tofu_inventory.sh         # Dynamic inventory from Terraform state
│   └── tofu_inventory.json       # Task metadata
├── data/                         # Hiera data
│   └── common.yaml               # Common configuration (includes eyaml encrypted data)
├── keys/                         # Eyaml encryption keys
│   ├── private_key.pkcs7.pem
│   └── public_key.pkcs7.pem
├── hiera.yaml                    # Hiera configuration
├── bolt-project.yaml             # Bolt project configuration
└── inventory.yaml                # Bolt inventory (dynamic via task plugin)
```

## Architecture Principles

### 1. Separation of Concerns

**Infrastructure Build (OpenTofu):**
- Provisions VMs on Proxmox
- Creates DNS records in Pihole
- Manages VM lifecycle
- **Does NOT** run provisioning/configuration

**Configuration Management (Bolt):**
- Runs after infrastructure is built
- Uses dynamic inventory from Terraform state
- Configures Puppet Enterprise, SCM, CD4PE
- Provisions agents

### 2. Tag-Based Inventory

All VMs are tagged in Terraform and dynamically discovered by Bolt:

**Infrastructure Tags:**
- `puppetinfra;puppet;prod;ubuntu` - Puppet Enterprise servers
- `puppetinfra;scm;prod;ubuntu` - SCM/Comply servers
- `puppetinfra;cd4pe;prod;ubuntu` - CD4PE servers
- `puppetagents;prod;ubuntu` - Puppet agent nodes

**Inventory Groups:**
- `puppet-infrastructure` - All infrastructure (tag: `puppetinfra`)
- `puppet-enterprise-nodes` - PE servers only (tag: `puppet`)
- `scm-nodes` - SCM servers only (tag: `scm`)
- `cd4pe-nodes` - CD4PE servers only (tag: `cd4pe`)
- `puppet-agents` - Agent nodes (tag: `puppetagents`)

Tag filtering uses exact matching with boundaries to prevent substring matches (e.g., `puppet` won't match `puppetinfra`).

### 3. Dynamic Inventory Task

The `tofu_inventory` task reads Terraform state and returns targets:

```bash
# Get all infrastructure
PT_dir=tf PT_tag_filter=puppetinfra ./tasks/tofu_inventory.sh

# Get only PE servers
PT_dir=tf PT_tag_filter=puppet ./tasks/tofu_inventory.sh

# Get all VMs (no filter)
PT_dir=tf ./tasks/tofu_inventory.sh
```

Returns JSON with targets including name, IP, and tags in vars:
```json
{
  "value": [
    {
      "name": "new-puppet.albatrossflavour.com",
      "uri": "192.168.7.100",
      "vars": {"tags": "prod;puppet;puppetinfra;ubuntu"}
    }
  ]
}
```

### 4. Hiera Configuration

Bolt plans use hiera lookups instead of hardcoded values:

**build_pe.pp:**
```puppet
$params = lookup('peadm::config', Hash, first, undef)
$targets = get_targets($params['primary_host'])
```

**build_scm.pp / build_cd4pe.pp:**
```puppet
$config = lookup('complyadm::config', Hash, first, undef)
$target_host = $config['resolvable_hostname']
$targets = get_targets($target_host)

$peadm_config = lookup('peadm::config', Hash, first, undef)
$puppet_server = $peadm_config['primary_host']
```

CSR attributes are separated to avoid module schema conflicts:
```puppet
$csr_attributes = lookup('complyadm::csr_attributes', Hash, first, {
  'datacenter' => 'lab',
  'role' => 'role::pe::scm',
  'environment' => 'production'
})
```

### 5. DNS Integration

Pihole DNS records are created automatically by Terraform:

```hcl
resource "pihole_dns_record" "new-puppet" {
  count  = var.puppet_pe ? 1 : 0
  domain = "new-puppet.${var.domain}"
  ip     = regexall("ip=([^/]+)", proxmox_vm_qemu.new-puppet-server[0].ipconfig0)[0][0]
}
```

DNS propagates immediately, so hostnames resolve before Bolt plans run.

### 6. SSH Configuration

Uses ed25519 keys for modern cryptography:

```yaml
config:
  transport: ssh
  ssh:
    private-key: ~/.ssh/id_ed25519
    user: tgreen
    run-as: root
    host-key-check: false
```

## Deployment Workflow

### Full Stack Deployment

1. **Provision Infrastructure:**
   ```bash
   cd tf
   tofu init
   tofu apply
   ```
   This creates VMs and DNS records. All resources are in state.

2. **Build Puppet Enterprise:**
   ```bash
   bolt plan run proxtoboltfu::build_pe
   ```

3. **Build SCM and CD4PE (can run in parallel):**
   ```bash
   bolt plan run proxtoboltfu::build_scm
   bolt plan run proxtoboltfu::build_cd4pe
   ```

4. **Post-Installation:**
   ```bash
   bolt plan run proxtoboltfu::fetch_ca_cert
   bolt plan run proxtoboltfu::puppet_access_login console_password=<password>
   ```

5. **Provision Agents (when you have agent VMs):**
   ```bash
   bolt command run 'puppet agent -t' --targets puppet-agents
   ```

### Adding New Infrastructure Types

To add a new type of infrastructure (e.g., compilers, monitoring):

1. **Create Terraform resource with appropriate tags:**
   ```hcl
   resource "proxmox_vm_qemu" "puppet-compiler" {
     tags = "puppetinfra;puppet;compiler;prod;ubuntu"
     # ...
   }
   ```

2. **Add inventory group in inventory.yaml:**
   ```yaml
   - name: puppet-compilers
     targets:
       _plugin: task
       task: proxtoboltfu::tofu_inventory
       parameters:
         dir: tf
         tag_filter: compiler
   ```

3. **Create corresponding Bolt plan in plans/**

Tags are extensible - use semicolon-separated values and filter on any tag.

## Key Patterns and Decisions

### Why Separate Terraform and Bolt?

**Previous approach:** Terraform `local-exec` provisioners ran Bolt plans during VM creation.

**Problems:**
- Inventory couldn't resolve targets (resources not in state until after provisioners complete)
- Complex path management required
- Failures during provisioning tainted resources
- Tight coupling made debugging difficult

**Current approach:** Terraform builds, Bolt configures.

**Benefits:**
- Clean separation of concerns
- Terraform state complete before Bolt runs (inventory works)
- Failed provisioning doesn't taint infrastructure
- Can re-run Bolt plans independently
- Easier testing and debugging

### Why Dynamic Inventory?

**Alternative:** Static inventory with hardcoded IPs.

**Problems:**
- Manual updates when infrastructure changes
- Drift between Terraform and inventory
- No automatic discovery

**Current approach:** Task plugin reads Terraform state.

**Benefits:**
- Single source of truth (Terraform state)
- Automatic discovery of new VMs
- Tag-based filtering for flexible grouping
- No manual synchronization

### Why Tag-Based Grouping?

**Alternative:** Separate inventory groups with hardcoded targets per type.

**Problems:**
- Rigid structure
- Manual updates when adding similar nodes
- Can't easily query "all infrastructure" or "all Ubuntu nodes"

**Current approach:** Flexible tags with filtered groups.

**Benefits:**
- Extensible (add compilers, HA nodes without changing structure)
- Multiple dimensions (by role, environment, OS, etc.)
- Single VM can belong to multiple logical groups
- Easy ad-hoc queries: `--targets puppet-infrastructure`

## Troubleshooting

### Inventory Not Showing Expected Targets

```bash
# Check what the task returns
PT_dir=tf ./tasks/tofu_inventory.sh

# Check specific filter
PT_dir=tf PT_tag_filter=puppet ./tasks/tofu_inventory.sh

# View Bolt's interpretation
bolt inventory show --detail
```

### DNS Not Resolving

Pihole resources may show authentication errors but still work. Verify:
```bash
dig new-puppet.albatrossflavour.com
nslookup new-puppet.albatrossflavour.com
```

### Plans Can't Find Targets

Ensure hostnames in hiera match DNS records:
```yaml
# data/common.yaml
peadm::config:
  primary_host: new-puppet.albatrossflavour.com  # Must match DNS
```

### Eyaml Decryption Fails

Ensure keys exist:
```bash
ls -la keys/
# Should show private_key.pkcs7.pem and public_key.pkcs7.pem
```

## File Relationships

### How Everything Connects

1. **Terraform** creates VMs with tags and IPs
2. **Terraform state** stores resource information
3. **tofu_inventory task** reads state, filters by tags, returns targets
4. **inventory.yaml** uses task plugin to populate groups dynamically
5. **Bolt plans** lookup config from **hiera** (data/common.yaml)
6. **Hiera** uses hostnames that match **DNS records** created by Terraform
7. **Plans** use `get_targets()` which resolves via **inventory groups**

The loop is closed: Terraform → State → Inventory → Plans → Hiera → Terraform (DNS)

## Important Notes

- **Never** hardcode IPs or hostnames in plans - use hiera
- **Always** tag VMs appropriately in Terraform
- **Test** tag filters before deploying: `PT_tag_filter=<tag> ./tasks/tofu_inventory.sh`
- **Extend** via tags, not by modifying inventory task
- Terraform and Bolt are **decoupled** - run independently
