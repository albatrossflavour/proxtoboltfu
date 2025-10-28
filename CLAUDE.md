# proxtoboltfu Project Structure

## Overview

This project uses OpenTofu (Terraform) to provision Proxmox VMs, Pihole for DNS management, and Puppet Bolt to configure infrastructure. The design separates infrastructure provisioning from configuration management for clean, predictable deployments.

## Directory Structure

```text
proxtoboltfu/
├── tf/                           # OpenTofu/Terraform configuration
│   ├── puppet.tf                 # Puppet Enterprise server (VMID 999)
│   ├── scm.tf                    # SCM/Comply server (VMID 998)
│   ├── cd4pe.tf                  # CD4PE server (VMID 997)
│   ├── dashboard.tf              # Dashboard server (VMID 996)
│   ├── nessus.tf                 # Nessus scanner (VMID 995)
│   ├── clients.tf                # Puppet agent clients (dynamic count)
│   ├── provider.tf               # Proxmox and Pihole providers
│   └── variables.tf              # Variable definitions
├── plans/                        # Puppet Bolt plans
│   ├── build_environment.pp      # Orchestrate full stack build
│   ├── build_pe.pp               # Build Puppet Enterprise server
│   ├── build_scm.pp              # Build SCM server
│   ├── build_cd4pe.pp            # Build CD4PE server
│   ├── build_dashboard.pp        # Build Dashboard server
│   ├── build_nessus.pp           # Build Nessus scanner
│   ├── build_agents.pp           # Build Puppet agent clients
│   ├── destroy_clients.pp        # Destroy agent clients with PE purge
│   ├── bootstrap_control_repo.pp # Create and push control repo to GitHub
│   ├── destroy_control_repo.pp   # Delete control repo from GitHub and local
│   ├── generate_nessus_pe_token.pp # Generate PE RBAC token for Nessus
│   ├── fetch_ca_cert.pp          # Download CA cert from PE server
│   └── puppet_access_login.pp    # Login to PE console
├── tasks/                        # Bolt tasks
│   ├── tofu_inventory.sh         # Dynamic inventory from Terraform state
│   └── tofu_inventory.json       # Task metadata
├── data/                         # Hiera data
│   ├── common.yaml               # Minimal common configuration
│   ├── roles/                    # Role-based hiera data
│   │   ├── role::pe::primary.yaml    # PE primary server config
│   │   ├── role::pe::scm.yaml        # SCM/Comply server config
│   │   ├── role::pe::cd4pe.yaml      # CD4PE server config
│   │   ├── role::pe::nessus.yaml     # Nessus scanner config
│   │   └── role::pe::dashboard.yaml  # Dashboard server config
│   ├── nodes/                    # Node-specific overrides (empty)
│   └── os/                       # OS-specific configuration
├── control-repo-template/        # Template for puppet-control-repo
│   ├── README.md
│   ├── Puppetfile                # Agent-side modules only
│   ├── hiera.yaml                # Uses absolute paths + trusted facts
│   ├── environment.conf
│   ├── manifests/
│   ├── site-modules/
│   ├── scripts/
│   └── data/                     # Placeholders (actual files copied at bootstrap)
├── keys/                         # Eyaml encryption keys
│   ├── private_key.pkcs7.pem
│   └── public_key.pkcs7.pem
├── hiera.yaml                    # Hiera configuration (Bolt-side, relative paths)
├── bolt-project.yaml             # Bolt project configuration
└── inventory.yaml                # Bolt inventory (dynamic via task plugin)
```

## Architecture Principles

### 1. Separation of Concerns

This project maintains a clear separation between infrastructure provisioning and configuration management:

**Infrastructure Provisioning (proxtoboltfu):**
- Uses OpenTofu to provision VMs on Proxmox
- Creates DNS records in Pihole
- Manages VM lifecycle
- Uses Puppet Bolt to build/configure infrastructure servers
- **Does NOT** manage agent configuration (that's the control repo's job)

**Agent Configuration Management (puppet-control-repo):**
- Separate Git repository created by `bootstrap_control_repo` plan
- Manages Puppet code for agent nodes
- Uses role-based hiera with trusted facts
- Deployed to agents via Code Manager
- Contains manifests, site-modules, Puppetfile for agent-side modules

**Key Distinction:**
- **proxtoboltfu** = Infrastructure automation (builds servers)
- **puppet-control-repo** = Configuration management (configures agents)

### 2. Tag-Based Inventory

All VMs are tagged in Terraform and dynamically discovered by Bolt:

**Key Classification Tags:**
- `puppetinfra` - All infrastructure servers
- `puppet` - Puppet Enterprise servers
- `scm` - SCM/Comply servers
- `cd4pe` - CD4PE servers
- `dashboard` - Dashboard servers
- `nessus` - Nessus scanners
- `puppetagents` - Puppet agent nodes

**Inventory Groups:**
- `puppet-infrastructure` - All infrastructure (filter: `puppetinfra`)
- `puppet-enterprise-nodes` - PE servers only (filter: `puppet`)
- `scm-nodes` - SCM servers only (filter: `scm`)
- `cd4pe-nodes` - CD4PE servers only (filter: `cd4pe`)
- `dashboard-nodes` - Dashboard servers only (filter: `dashboard`)
- `nessus-nodes` - Nessus scanners only (filter: `nessus`)
- `puppet-agents` - Agent nodes (filter: `puppetagents`)

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
      "uri": "192.168.10.100",
      "vars": {"tags": "prod;puppet;puppetinfra;ubuntu"}
    }
  ]
}
```

The script handles multiple IP scenarios:
- Static IPs: Extracted from `ipconfig0` parameter
- DHCP: Falls back to using hostname for DNS resolution
- Guest Agent: Uses `default_ipv4_address` if available from Proxmox guest agent

### 4. Dual-Repository Hiera Architecture

The project uses two separate repositories with different hiera configurations:

#### proxtoboltfu Hiera (Bolt-side)

**Purpose:** Infrastructure builds where Bolt runs on localhost
**Location:** `proxtoboltfu/hiera.yaml`
**Key Paths:** Relative (`keys/private_key.pkcs7.pem`)

```yaml
hierarchy:
  - name: "Eyaml hierarchy"
    lookup_key: eyaml_lookup_key
    options:
      pkcs7_private_key: keys/private_key.pkcs7.pem
      pkcs7_public_key: keys/public_key.pkcs7.pem
    paths:
      - "roles/role::pe::primary.yaml"
      - "roles/role::pe::scm.yaml"
      - "roles/role::pe::cd4pe.yaml"
      - "roles/role::pe::nessus.yaml"
      - "roles/role::pe::dashboard.yaml"
      - "common.yaml"
```

**Note:** Bolt doesn't have trusted facts, so all role files are listed explicitly.

#### puppet-control-repo Hiera (Agent-side)

**Purpose:** Agent configuration via Code Manager
**Location:** `puppet-control-repo/hiera.yaml`
**Key Paths:** Absolute (`/etc/puppetlabs/secure/keys/...`)

```yaml
hierarchy:
  - name: "Eyaml hierarchy"
    lookup_key: eyaml_lookup_key
    options:
      pkcs7_private_key: /etc/puppetlabs/secure/keys/private_key.pkcs7.pem
      pkcs7_public_key: /etc/puppetlabs/secure/keys/public_key.pkcs7.pem
    paths:
      - "nodes/%{trusted.certname}.yaml"
      - "roles/%{trusted.extensions.pp_role}.yaml"
      - "os/%{facts.os.name}-%{facts.os.release.full}.yaml"
      - "os/%{facts.os.name}-%{facts.os.release.major}.yaml"
      - "common.yaml"
```

**Note:** Uses trusted facts and facts for dynamic role/node/OS lookups on agents.

#### Hiera Lookups in Bolt Plans

Bolt plans use hiera lookups instead of hardcoded values:

```puppet
# Lookup PE config
$params = lookup('peadm::config', Hash, first, undef)
$targets = get_targets($params['primary_host'])

# Lookup infrastructure config
$config = lookup('complyadm::config', Hash, first, undef)
$target_host = $config['resolvable_hostname']

# Lookup CSR attributes (separated to avoid schema conflicts)
$csr_attributes = lookup('complyadm::csr_attributes', Hash, first, {
  'datacenter' => 'lab',
  'role' => 'role::pe::scm',
  'environment' => 'production'
})
```

#### Single Source of Truth: r10k_remote

Both `bootstrap_control_repo` and `generate_nessus_pe_token` plans extract the control repo location from `peadm::config['r10k_remote']`:

```puppet
# Extract from r10k_remote (no duplicate config)
$pe_params = lookup('peadm::config', Hash, first, undef)
$repo_url = $pe_params['r10k_remote']
# e.g., git@github.com:albatrossflavour/puppet-control-repo.git

# Parse repo name and GitHub username
$url_parts = split($repo_url, '/')
$repo_name_with_ext = $url_parts[-1]
$control_repo_name = regsubst($repo_name_with_ext, '\.git$', '')
$github_username = regsubst($repo_url, '^git@github\.com:([^/]+)/.*$', '\1')
```

This ensures consistency - the control repo location is defined once in `data/roles/role::pe::primary.yaml`.

### 5. Control Repository Template

The `control-repo-template/` directory contains static template files that get copied during bootstrap:

**Structure:**
```
control-repo-template/
├── README.md
├── Puppetfile              # Agent-side modules only (NOT Bolt modules)
├── hiera.yaml              # Uses absolute paths for PE server
├── environment.conf
├── manifests/
├── site-modules/
├── scripts/
└── data/
    ├── common.yaml         # Placeholder (actual file copied at bootstrap)
    ├── roles/              # Empty (actual files copied at bootstrap)
    ├── nodes/              # Empty
    └── os/                 # Empty (actual files copied at bootstrap)
```

**Key differences from proxtoboltfu:**
- Puppetfile contains only agent-side modules (no peadm, complyadm, cd4peadm)
- hiera.yaml uses absolute paths (`/etc/puppetlabs/secure/keys/`)
- hiera.yaml uses trusted facts and facts for dynamic lookups
- Data files are placeholders - actual data copied from proxtoboltfu at bootstrap time

### 6. DNS Integration

Pihole DNS records are created automatically by Terraform:

```hcl
resource "pihole_dns_record" "new-puppet" {
  count  = var.puppet_pe ? 1 : 0
  domain = "new-puppet.${var.domain}"
  ip     = regexall("ip=([^/]+)", proxmox_vm_qemu.new-puppet-server[0].ipconfig0)[0][0]
}
```

DNS propagates immediately, so hostnames resolve before Bolt plans run.

**DNS Search Domain Configuration:**

VMs are configured with static IPs and explicit DNS settings via
cloud-init. The `searchdomain` parameter in Terraform sets the DNS
search domain, overriding any inherited settings from Proxmox
templates:

```hcl
searchdomain = var.domain
nameserver   = "192.168.9.2 192.168.9.3"
```

This ensures VMs use `albatrossflavour.com` as their search domain,
regardless of the Proxmox host's DNS configuration. If Proxmox
templates are set to "use host settings", Terraform will override
this during VM creation.

### 7. SSH Configuration

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

### Full Stack Deployment (Single Command)

```bash
bolt plan run proxtoboltfu::build_environment
```

This orchestrates the complete deployment:
1. Provisions infrastructure with OpenTofu (VMs + DNS)
2. Builds Puppet Enterprise server
3. Builds additional infrastructure (SCM, CD4PE, Dashboard, Nessus) in parallel
4. Builds agent nodes if any exist

To skip infrastructure provisioning (if VMs already exist):
```bash
bolt plan run proxtoboltfu::build_environment apply_terraform=false
```

### Manual Step-by-Step Deployment

If you prefer manual control:

1. **Provision Infrastructure:**
   ```bash
   cd tf
   tofu init
   tofu apply -parallelism=1
   ```
   This creates VMs and DNS records. All resources are in state.
   Serial execution prevents Pihole API session exhaustion.

2. **Build Puppet Enterprise:**
   ```bash
   bolt plan run proxtoboltfu::build_pe
   ```

3. **Build Additional Infrastructure (can run in parallel):**
   ```bash
   bolt plan run proxtoboltfu::build_scm
   bolt plan run proxtoboltfu::build_cd4pe
   bolt plan run proxtoboltfu::build_dashboard
   bolt plan run proxtoboltfu::build_nessus
   ```

4. **Build Agent Nodes:**
   ```bash
   bolt plan run proxtoboltfu::build_agents
   ```

### Managing Agent Clients

**Client Configuration** (tf/terraform.tfvars):
```hcl
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

# Client Counts per Environment
prod_clients = 1  # Number of clients per OS in production
dev_clients  = 0  # Number of clients per OS in development
```

With `enable_ubuntu=true`, `prod_clients=1`, `dev_clients=0`:
- Creates 3 prod clients (one for each Ubuntu version: 20.04, 22.04, 24.04)
- Creates 0 dev clients
- Each client gets static IP assigned sequentially starting at .10
- DNS records created automatically

**Deploy Clients:**
```bash
cd tf && tofu apply -parallelism=1  # Create VMs
bolt plan run proxtoboltfu::build_agents  # Configure agents
```

**Destroy Clients:**
```bash
# Preview what will be destroyed
bolt plan run proxtoboltfu::destroy_clients

# Actually destroy (purges from PE, then destroys VMs)
bolt plan run proxtoboltfu::destroy_clients confirm=true
```

The destroy process automatically:
1. Lists agents to be destroyed
2. Purges agent certificates from Puppet Enterprise (via destroy provisioner in Terraform)
3. Destroys VMs
4. Removes DNS records

### Client Architecture

**clients.tf** uses for_each with locals to dynamically create agents:

```hcl
locals {
  os_configurations = {
    "ubuntu-2004-prod" = {
      os_family    = "ubuntu"
      version      = "2004"
      environment  = "prod"
      template     = "template-Ubuntu-2004"
      vmid_base    = "91230"
      enabled      = var.enable_ubuntu
      client_count = var.prod_clients
    }
    # ... more OS configurations
  }

  # Sequential IP allocation starting at .10
  puppet_clients = [
    for idx, client in local.puppet_clients_base : merge(client, {
      ip_address = "192.168.10.${10 + idx}"
    })
  ]
}
```

**Features:**
- Single resource definition for all agent types
- Sequential static IP allocation
- Automatic DNS record creation
- Destroy provisioner for PE purge

**Scaling:**
- Enable OS families via `enable_*` flags
- Set client counts with `prod_clients` and `dev_clients`
- Total agents = (enabled OS versions) × (prod + dev clients)
- Example: 9 OS families × 2 versions avg × (5 prod + 3 dev) = 144 agents

### Managing the Control Repository

The control repository is created and destroyed using automated plans:

#### Bootstrap Control Repo

Creates the puppet-control-repo from the r10k_remote configuration:

```bash
# Create and push control repo to GitHub
bolt plan run proxtoboltfu::bootstrap_control_repo push=true
```

**What it does:**
1. Extracts repo URL from `peadm::config['r10k_remote']`
2. Creates GitHub repository using `gh` CLI
3. Clones puppetlabs/control-repo template
4. Copies manifests, site-modules, scripts from `control-repo-template/`
5. Copies current hiera data from `proxtoboltfu/data/` (with generated values)
6. Creates production and development branches
7. Leaves repo checked out on production branch
8. Pushes both branches to GitHub

**Safety features:**
- Checks if local directory exists first
- Requires `overwrite=true` to remove existing directory
- Auto-creates GitHub repo if it doesn't exist

**Parameters:**
- `work_dir` - Directory to clone into (default: ~/dev)
- `push` - Whether to push to GitHub (default: false)
- `overwrite` - Remove existing directory (default: false)

#### Destroy Control Repo

Removes the control repository from GitHub and local filesystem:

```bash
# Dry run - shows what would be deleted
bolt plan run proxtoboltfu::destroy_control_repo

# Actually delete
bolt plan run proxtoboltfu::destroy_control_repo confirm=true
```

**What it does:**
1. Extracts repo URL from `peadm::config['r10k_remote']`
2. Deletes local directory (~/dev/puppet-control-repo)
3. Deletes GitHub repository using `gh` CLI

**Safety features:**
- Defaults to dry run (confirm=false)
- Shows exactly what will be deleted before proceeding
- Handles cases where repo or directory don't exist

#### Generate Nessus PE Token

Generates and stores PE RBAC token for Nessus Transformer:

```bash
# Generate token (writes to control repo if it exists, otherwise proxtoboltfu)
bolt plan run proxtoboltfu::generate_nessus_pe_token commit_changes=true regenerate=false
```

**Smart token placement:**
- Checks if control repo exists locally
- If yes: writes to `control-repo/data/roles/role::pe::nessus.yaml`
- If no: writes to `proxtoboltfu/data/roles/role::pe::nessus.yaml`
- Ensures production branch is checked out before writing to control repo

**Parameters:**
- `regenerate` - Force regeneration even if token exists (default: false)
- `commit_changes` - Git commit and push (default: false)
- `work_dir` - Directory containing repos (default: ~/dev)

**When using control repo:**
- Commits to production branch
- Pushes to GitHub
- Runs `puppet-code deploy production --wait`

### Adding New Infrastructure Types

To add a new type of infrastructure (e.g., compilers):

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

### Why Dual Repository Architecture?

**Alternative:** Single repo containing both infrastructure automation and agent configuration.

**Problems:**
- Infrastructure build code mixed with agent Puppet code
- Bolt modules (peadm, complyadm) deployed to agents unnecessarily
- Can't use trusted facts in hiera (Bolt doesn't have them)
- Eyaml key paths differ (relative for Bolt, absolute for PE server)
- Agent changes trigger infrastructure rebuilds
- No clear separation between build-time and runtime

**Current approach:** Separate repos with distinct purposes.

**Benefits:**
- **proxtoboltfu**: Infrastructure builds, uses Bolt, includes build modules
- **puppet-control-repo**: Agent config, uses Code Manager, excludes build modules
- Each repo has appropriate hiera configuration:
  - proxtoboltfu: Explicit file listing (no trusted facts)
  - control-repo: Trusted facts and facts-based hierarchy
- Eyaml keys in correct locations for each use case
- Agent changes don't affect infrastructure code
- Clear lifecycle: bootstrap creates, destroy removes
- Single source of truth via r10k_remote

**Implementation details:**
- Bootstrap plan copies current data from proxtoboltfu (with generated values)
- Token generation intelligently detects which repo to update
- Both repos use same role-based structure (different hiera lookups)
- Control repo created on demand, not checked into proxtoboltfu

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

**Infrastructure Build Flow (proxtoboltfu):**
1. **Terraform** creates VMs with tags, IPs, and DNS records
2. **Terraform state** stores resource information
3. **tofu_inventory task** reads state, filters by tags, returns targets
4. **inventory.yaml** uses task plugin to populate groups dynamically
5. **Bolt plans** lookup config from **proxtoboltfu hiera** (data/roles/*.yaml)
6. **Hiera** resolves hostnames that match **DNS records** created by Terraform
7. **Plans** use `get_targets()` which resolves via **inventory groups**
8. **Plans** configure infrastructure servers using Bolt modules (peadm, complyadm, etc.)

**Control Repo Flow (puppet-control-repo):**
1. **bootstrap_control_repo** plan extracts location from r10k_remote
2. Creates GitHub repo and clones puppetlabs template
3. Copies current data from **proxtoboltfu/data/** (preserves generated values)
4. Pushes to GitHub with production and development branches
5. **Code Manager** on PE server deploys from r10k_remote
6. **Agents** connect to PE server and fetch catalog
7. **PE server hiera** uses trusted facts to lookup role-based data
8. Agents apply configuration from site-modules

**Dual-Repo Integration:**
- r10k_remote in peadm::config is single source of truth
- Bootstrap copies data with eyaml-encrypted values
- Token generation updates whichever repo exists locally
- Both repos share same role-based structure (different lookups)

## Important Notes

- **Never** hardcode IPs or hostnames in plans - use hiera
- **Always** tag VMs appropriately in Terraform
- **Test** tag filters before deploying: `PT_tag_filter=<tag> ./tasks/tofu_inventory.sh`
- **Extend** via tags, not by modifying inventory task
- Terraform and Bolt are **decoupled** - run independently
- **Control repo** is created on demand - not checked into proxtoboltfu
- **r10k_remote** is the single source of truth for control repo location
- **Bootstrap** before first agent run, **destroy** when tearing down
- **Token generation** works with both repos - detects which one to update

## Task Management

This project uses **OmniFocus** for task tracking via the MCP OmniFocus integration. Tasks are stored in the **proxtoboltfu** project within the "Puppet Tech Stuff" folder.

**Task Tags:**
- `<Code>` - Code implementation tasks
- `<Admin>` - Documentation and administrative tasks
- `<Research>` - Investigation and research tasks

**Integration:**
- Claude Code can read, create, and update OmniFocus tasks
- High-priority tasks are flagged in OmniFocus
- Tasks are organized by project context
- No local .todo.txt files - OmniFocus is the single source of truth

## Working Principles

### Problem Solving Approach

**NEVER suggest workarounds before diagnosis:**
- ❌ "Just run it again" - for Puppet, Tofu/Terraform, or any tool
- ❌ Adding retries, dependencies, or parallelism limits without understanding the root cause
- ❌ Removing functionality to avoid dealing with issues

**ALWAYS diagnose first, then fix properly:**
- ✅ Check logs first - application logs, system logs, API logs
- ✅ Investigate errors and system behaviour
- ✅ Identify the actual constraint or bottleneck
- ✅ Address the root cause with proper configuration
- ✅ Performance tuning over artificial limitations

**Example - Pihole API Session Exhaustion:**
- ❌ Wrong: Remove Pihole from Terraform entirely, switch to Route53/PowerDNS, manage DNS separately
- 🔍 Diagnostic steps: Add `depends_on` to test serialization, use `-parallelism=1` to eliminate concurrency
- ✅ Right: Increase `webserver.api.max_sessions` in `/etc/pihole/pihole.toml` from 16 to 64 to accommodate session leaks in the provider

**Principle: Right first time**
If it requires multiple runs, retries, or manual intervention to succeed, it's not right. Fix the underlying issue.
