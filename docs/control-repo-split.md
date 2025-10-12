# Control Repo Split - Technical Implementation Plan

## Executive Summary

**Problem:** Bolt's `bolt module install` overwrites the Puppetfile, creating an unsolvable conflict between Bolt's module management and Puppet control repo requirements.

**Solution:** Split Puppet control repo into a separate repository with proper Code Manager integration, while proxtoboltfu retains only bootstrap/provisioning code.

**Key Innovation:** Day-2 operations (upgrades, maintenance) read configuration from running infrastructure (which uses control repo), NOT from Bolt's hiera. This eliminates drift issues entirely.

**Implementation:** 7 phases covering bootstrap, hiera restructuring, Code Manager setup, cleanup, and day-2 operational patterns.

**Outcome:**
- Clean architectural separation (bootstrap vs operations)
- Standard Puppet control repo structure with role-based hiera
- No Puppetfile conflicts
- No hiera drift problems
- Production-ready infrastructure management

---

## Problem

**Root cause:** Bolt manages its module dependencies via `bolt-project.yaml`, and when you run `bolt module install`, it **overwrites the Puppetfile** with modules needed for Bolt operations.

**The conflict:** A single Puppetfile cannot serve two purposes:
- **Bolt's Puppetfile:** Auto-generated from `bolt-project.yaml`, contains modules for infrastructure provisioning (peadm, complyadm, cd4peadm) installed to `.modules/`
- **Control repo Puppetfile:** Hand-crafted for Puppet code, contains modules for agent configuration deployed by Code Manager to `/etc/puppetlabs/code/environments/`

**Impact:**
- Running `bolt module install` destroys the control repo Puppetfile
- Ongoing Bolt operations (maintenance, upgrades) will repeatedly regenerate the Puppetfile, overwriting control repo module definitions
- Cannot maintain stable Puppet module dependencies for agents while using Bolt tooling

## Solution

Split the Puppet control repo into a separate repository, using the puppetlabs/control-repo template as foundation, then deploy via Code Manager.

**Critical Design Decision:** Control repo becomes the source of truth for ALL operational configuration after initial bootstrap. Bolt's day-2 plans read configuration from running infrastructure (not stale Bolt hiera), eliminating drift problems.

---

## Implementation Steps

### Phase 1: Bootstrap Control Repo from Template

#### 1.1 Clone Puppetlabs Control Repo Template

```bash
cd ~/dev
git clone https://github.com/puppetlabs/control-repo.git puppet-control-repo
cd puppet-control-repo
rm -rf .git
git init
```

**Template provides:**
- Standard directory structure (`manifests/`, `site-modules/`, `data/`)
- Example `Puppetfile` with common modules
- `environment.conf` configured for Code Manager
- `hiera.yaml` for environment-level data
- Git hooks and scripts

#### 1.2 Configure Git Remote

```bash
git remote add origin <your-git-server>/puppet-control-repo.git
```

**Options:**
- GitHub/GitLab/Bitbucket
- Local Gitea/Gogs
- PE-integrated Git (if using CD4PE)

---

### Phase 2: Copy Required Files from proxtoboltfu

#### 2.1 Copy Control Repo Template Files

```bash
# Copy from template directory
cp -r ~/dev/proxtoboltfu/control-repo-template/manifests .
cp -r ~/dev/proxtoboltfu/control-repo-template/site-modules .
cp -r ~/dev/proxtoboltfu/control-repo-template/scripts .
cp -r ~/dev/proxtoboltfu/control-repo-template/keys .
cp ~/dev/proxtoboltfu/control-repo-template/environment.conf .
cp ~/dev/proxtoboltfu/control-repo-template/hiera.yaml .

# Verify structure
ls -la
tree -L 2 manifests/ site-modules/
```

**Template provides:**
- `manifests/site.pp` - Node classification via `$trusted['extensions']['pp_role']`
- `site-modules/profile/` - Infrastructure profiles
- `site-modules/role/` - Role definitions
- `scripts/` - Config version tracking for Code Manager
- `environment.conf` - Environment configuration
- `hiera.yaml` - Eyaml-enabled hiera config
- `keys/` - Eyaml encryption keys

#### 2.2 Create Control Repo Puppetfile

**DO NOT** copy Bolt's Puppetfile directly. Create new Puppetfile for Puppet modules only:

```bash
cat > Puppetfile <<'EOF'
forge 'https://forge.puppet.com'

# Core Puppet Enterprise modules (required for profiles)
mod 'puppetlabs/stdlib'
mod 'puppetlabs/concat'
mod 'puppetlabs/apt'
mod 'puppetlabs/inifile'
mod 'puppetlabs/firewall'
mod 'puppetlabs/docker'
mod 'puppetlabs/node_manager'
mod 'puppetlabs/puppet_agent'

# Add additional modules as needed by your profiles
# Review site-modules profiles to identify dependencies

EOF
```

**Analysis needed:**
- Review `site-modules/profile/manifests/**/*.pp` for module dependencies
- Add only modules required by Puppet code (not Bolt modules like peadm, complyadm, cd4peadm)

#### 2.3 Update Hiera Configuration for Role-Based Data

Update the hiera.yaml to follow best practices using trusted facts for role-based lookups:

```bash
cat > hiera.yaml <<'EOF'
---
version: 5

defaults:
  datadir: data
  data_hash: yaml_data

hierarchy:
  - name: 'Eyaml hierarchy'
    lookup_key: eyaml_lookup_key
    options:
      pkcs7_private_key: keys/private_key.pkcs7.pem
      pkcs7_public_key: keys/public_key.pkcs7.pem
    paths:
      - "nodes/%{trusted.certname}.yaml"
      - "roles/%{trusted.extensions.pp_role}.yaml"
      - 'common.yaml'
EOF
```

**Hierarchy structure:**
1. Per-node data (highest priority): `data/nodes/<certname>.yaml`
2. Per-role data: `data/roles/<pp_role>.yaml` (uses trusted extension from CSR)
3. Common data (lowest priority): `data/common.yaml`

#### 2.4 Create Role-Based Hiera Data Files

```bash
# Create directory structure
mkdir -p data/roles data/nodes

# Extract role-specific data from proxtoboltfu hiera files
# Create role-specific hiera files based on existing configurations

# Dashboard role data
cat > data/roles/role::pe::dashboard.yaml <<'EOF'
---
# Copy dashboard config from proxtoboltfu/data/common.yaml
# Including encrypted passwords and settings
EOF

# Nessus role data
cat > data/roles/role::pe::nessus.yaml <<'EOF'
---
# Copy nessus config from proxtoboltfu/data/common.yaml
EOF

# PE Primary role data
cat > data/roles/role::pe::primary.yaml <<'EOF'
---
# Copy profile::pe::agent_types from proxtoboltfu/data/pe.yaml
# This defines which agent platform repos to enable
EOF

# SCM role data
cat > data/roles/role::pe::scm.yaml <<'EOF'
---
# SCM-specific configuration if needed
EOF

# CD4PE role data
cat > data/roles/role::pe::cd4pe.yaml <<'EOF'
---
# CD4PE-specific configuration if needed
EOF

# Common data (applies to all nodes)
cat > data/common.yaml <<'EOF'
---
# Common configuration for all nodes
# Base profile settings, SOE configurations, etc.
EOF
```

**Data migration process:**

1. Review `~/dev/proxtoboltfu/data/common.yaml`:
   - Extract `dashboard::config` and `dashboard::csr_attributes` → `data/roles/role::pe::dashboard.yaml`
   - Extract `nessus::config` and `nessus::csr_attributes` → `data/roles/role::pe::nessus.yaml`

2. Review `~/dev/proxtoboltfu/data/pe.yaml`:
   - Extract `profile::pe::agent_types` → `data/roles/role::pe::primary.yaml`
   - Leave `peadm::config` in proxtoboltfu (Bolt operational data)

3. Review `~/dev/proxtoboltfu/data/scm.yaml` and `~/dev/proxtoboltfu/data/cd4pe.yaml`:
   - Leave operational config in proxtoboltfu
   - Copy any profile-specific settings to respective role files

**Benefits of this structure:**
- Follows Puppet hiera best practices
- Uses trusted facts (CSR extensions) for role classification
- Clear separation: role-specific data isolated in `data/roles/`
- Node-specific overrides possible in `data/nodes/`
- Common defaults in `data/common.yaml`

**Note:** Eyaml encryption works across all hierarchy levels. Copy encrypted values directly from proxtoboltfu hiera files.

#### 2.5 Review and Clean Template Files

```bash
# Remove template examples not needed
rm -f site-modules/profile/examples/*
rm -f site-modules/role/examples/*

# Keep .gitignore from template (already configured properly)
# Review README.md from template and update for your environment
```

---

### Phase 3: Commit and Push Control Repo

#### 3.1 Initial Commit

```bash
git add .
git commit -m "Initial control repo

Bootstrapped from puppetlabs/control-repo template
Copied production code from proxtoboltfu:
- manifests/site.pp (role-based classification)
- site-modules/profile (infrastructure profiles)
- site-modules/role (role definitions)
- environment.conf and scripts/

Puppetfile configured for required Forge modules"
```

#### 3.2 Create Production Branch

```bash
# Code Manager typically uses branch = environment mapping
git checkout -b production
git push -u origin production

# Optionally create development branch
git checkout -b development
git push -u origin development
```

**Branch strategy:**
- `production` branch → production environment in PE
- `development` branch → development environment
- Feature branches as needed

---

### Phase 4: Configure Code Manager in Puppet Enterprise

#### 4.1 Access Puppet Enterprise Console

Navigate to: `https://new-puppet.albatrossflavour.com`

#### 4.2 Configure Code Manager Settings

**Console → Classification → PE Master group:**

Add/modify parameters:
```yaml
puppet_enterprise::profile::master::code_manager_auto_configure: true
puppet_enterprise::profile::master::r10k_remote: '<git-repo-url>'
puppet_enterprise::profile::master::r10k_private_key: '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa'
```

**Git repository URL formats:**
- SSH: `git@github.com:username/puppet-control-repo.git`
- HTTPS: `https://github.com/username/puppet-control-repo.git`

#### 4.3 Set Up Deploy Key (SSH)

**On PE server:**
```bash
# Generate deploy key
ssh-keygen -t ed25519 -f /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa -C "pe-code-manager"

# Set permissions
chown pe-puppet:pe-puppet /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa*
chmod 600 /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa

# Copy public key
cat /etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa.pub
```

**Add deploy key to Git repository:**
- GitHub: Settings → Deploy keys → Add deploy key
- Paste public key content
- Grant read-only access (Code Manager only pulls)

#### 4.4 Configure Puppet Access Token

**Generate token for Code Manager API:**
```bash
# On workstation or PE server
puppet access login --lifetime 1y

# Generate deployment token
puppet-code deploy --token-file ~/.puppetlabs/token --dry-run
```

**Alternative:** Use PE console to generate RBAC token for Code Manager user

#### 4.5 Test Code Manager Configuration

```bash
# On PE server, run Puppet to apply Code Manager config
puppet agent -t

# Verify Code Manager status
puppet-code status

# Expected output: Shows configured environments and last deploy
```

---

### Phase 5: Deploy Control Repo via Code Manager

#### 5.1 Initial Deployment

**Via Bolt plan (recommended):**

Create new plan in proxtoboltfu:
```puppet
# plans/deploy_control_repo.pp
plan proxtoboltfu::deploy_control_repo(
  Optional[Boolean] $wait = true,
) {
  $pe_config = lookup('peadm::config', Hash)
  $pe_server = $pe_config['primary_host']
  $targets = get_targets($pe_server)

  out::message("Deploying control repo via Code Manager...")

  # Deploy all environments
  $result = run_command(
    'puppet-code deploy --all --wait',
    $targets,
  )

  if $result.ok {
    out::message("Control repo deployed successfully")
    out::message($result.first.value['stdout'])
  } else {
    fail_plan("Failed to deploy control repo: ${result.first.value['stderr']}")
  }

  return $result
}
```

**Via CLI:**
```bash
# From PE server
puppet-code deploy production --wait

# Or deploy all environments
puppet-code deploy --all --wait
```

#### 5.2 Verify Deployment

**Check environment paths:**
```bash
# On PE server
ls -la /etc/puppetlabs/code/environments/

# Should show production/ directory with your control repo contents
ls -la /etc/puppetlabs/code/environments/production/
```

**Expected structure:**
```
/etc/puppetlabs/code/environments/production/
├── environment.conf
├── hiera.yaml
├── manifests/
│   └── site.pp
├── modules/          # Forge modules from Puppetfile
├── site-modules/     # Your profiles and roles
│   ├── profile/
│   └── role/
└── data/
```

#### 5.3 Test Agent Classification

**On an agent node:**
```bash
# Request catalog from PE
puppet agent -t --environment production

# Verify role is applied
grep pp_role /opt/puppetlabs/puppet/cache/state/classes.txt
```

**Expected:** Node classified with role from CSR attributes, catalog compiles successfully

---

### Phase 6: Update proxtoboltfu Repository

#### 6.1 Move Control Repo Files to Template Directory

```bash
cd ~/dev/proxtoboltfu

# Create template directory structure
mkdir -p control-repo-template/{manifests,site-modules,scripts,keys,data}

# Move control repo files to template location (preserving in git history)
git mv manifests/ control-repo-template/
git mv site-modules/ control-repo-template/
git mv environment.conf control-repo-template/
git mv scripts/config_version.sh control-repo-template/scripts/
git mv scripts/config_version.rb control-repo-template/scripts/
git mv scripts/code_manager_config_version.rb control-repo-template/scripts/

# Copy eyaml keys to template (keep originals for Bolt)
cp keys/private_key.pkcs7.pem control-repo-template/keys/
cp keys/public_key.pkcs7.pem control-repo-template/keys/

# Create template hiera.yaml with role-based hierarchy
cat > control-repo-template/hiera.yaml <<'EOF'
---
version: 5

defaults:
  datadir: data
  data_hash: yaml_data

hierarchy:
  - name: 'Eyaml hierarchy'
    lookup_key: eyaml_lookup_key
    options:
      pkcs7_private_key: keys/private_key.pkcs7.pem
      pkcs7_public_key: keys/public_key.pkcs7.pem
    paths:
      - "nodes/%{trusted.certname}.yaml"
      - "roles/%{trusted.extensions.pp_role}.yaml"
      - 'common.yaml'
EOF

# Create template data structure with role-based files
mkdir -p control-repo-template/data/roles control-repo-template/data/nodes

# Create example role data files
cat > control-repo-template/data/roles/role::pe::dashboard.yaml <<'EOF'
---
# Dashboard role configuration
# Migrated from proxtoboltfu/data/common.yaml
dashboard::config:
  resolvable_hostname: new-dashboard.albatrossflavour.com
dashboard::csr_attributes:
  datacenter: lab
  role: role::pe::dashboard
  environment: production
# dashboard::grafana_admin_password: <copy encrypted value>
EOF

cat > control-repo-template/data/roles/role::pe::nessus.yaml <<'EOF'
---
# Nessus role configuration
# Migrated from proxtoboltfu/data/common.yaml
nessus::config:
  resolvable_hostname: new-nessus.albatrossflavour.com
nessus::csr_attributes:
  datacenter: lab
  role: role::pe::nessus
  environment: production
EOF

cat > control-repo-template/data/roles/role::pe::primary.yaml <<'EOF'
---
# PE Primary server configuration
# Migrated from proxtoboltfu/data/pe.yaml
profile::pe::agent_types:
  - pe_repo::platform::el_7_x86_64
  - pe_repo::platform::el_8_x86_64
  - pe_repo::platform::el_9_x86_64
  - pe_repo::platform::ubuntu_2004_amd64
  - pe_repo::platform::ubuntu_2204_amd64
  - pe_repo::platform::ubuntu_2404_amd64
  - pe_repo::platform::debian_11_amd64
  - pe_repo::platform::debian_12_amd64
  - pe_repo::platform::sles_15_x86_64
  - pe_repo::platform::windows_x86_64
EOF

cat > control-repo-template/data/roles/role::pe::scm.yaml <<'EOF'
---
# SCM role configuration (if needed beyond profile defaults)
EOF

cat > control-repo-template/data/roles/role::pe::cd4pe.yaml <<'EOF'
---
# CD4PE role configuration (if needed beyond profile defaults)
EOF

cat > control-repo-template/data/common.yaml <<'EOF'
---
# Common configuration for all nodes
# Base profile settings, SOE configurations
EOF

# Create template README
cat > control-repo-template/README.md <<'EOF'
# Control Repo Template

This directory contains template files for bootstrapping the Puppet control repository.

## Files

- `manifests/site.pp` - Main manifest with role-based node classification
- `site-modules/` - Role and profile modules
- `scripts/` - Config version scripts for Code Manager
- `environment.conf` - Environment configuration
- `hiera.yaml` - Hiera configuration with eyaml support
- `keys/` - Eyaml encryption keys

## Usage

Copy these files when creating a new control repo:

```bash
cd ~/dev/puppet-control-repo
cp -r ~/dev/proxtoboltfu/control-repo-template/manifests .
cp -r ~/dev/proxtoboltfu/control-repo-template/site-modules .
cp -r ~/dev/proxtoboltfu/control-repo-template/scripts .
cp -r ~/dev/proxtoboltfu/control-repo-template/keys .
cp ~/dev/proxtoboltfu/control-repo-template/environment.conf .
cp ~/dev/proxtoboltfu/control-repo-template/hiera.yaml .
```

See `docs/control-repo-split.md` for full implementation details.
EOF

# Keep Bolt-specific files in root
# - Puppetfile (Bolt modules, auto-generated from bolt-project.yaml)
# - plans/ (Bolt plans)
# - tasks/ (Bolt tasks)
# - data/ (Bolt operational data)
# - hiera.yaml (Bolt hiera config)
# - keys/ (eyaml keys for Bolt hiera)
```

#### 6.2 Clean Bootstrap Hiera After Deployment

**Run after successful control repo deployment:**

```bash
# Clean up migrated hiera values
bolt plan run proxtoboltfu::cleanup_bootstrap_hiera confirm=true
```

This removes values that have migrated to control repo and replaces them with pointers.

**Before cleanup (data/common.yaml):**
```yaml
dashboard::config:
  resolvable_hostname: new-dashboard.albatrossflavour.com
dashboard::grafana_admin_password: ENC[PKCS7,...]
nessus::config:
  resolvable_hostname: new-nessus.albatrossflavour.com
```

**After cleanup (data/common.yaml):**
```yaml
---
# WARNING: BOOTSTRAP HIERA - VALUES MIGRATED TO CONTROL REPO
#
# This file previously contained operational configuration.
# Those values now live in: puppet-control-repo/data/roles/
#
# Removed (now in control repo):
# - dashboard::config → data/roles/role::pe::dashboard.yaml
# - dashboard::grafana_admin_password → data/roles/role::pe::dashboard.yaml
# - nessus::config → data/roles/role::pe::nessus.yaml
#
# See: docs/control-repo-split.md
#
# This file intentionally minimal - add values only if needed for bootstrap.
```

**Values removed from Bolt hiera:**
- Application passwords (dashboard, nessus)
- Console password
- Forge authorization tokens
- Code Manager credentials
- Agent platform repositories

**Values retained in Bolt hiera:**
- PE license key (needed for reprovisioning)
- Initial version pins (for reference)
- Bootstrap network config (hostnames)
- CA/certificate settings

**Benefits:**
- Eliminates confusion about where values live
- Prevents using stale Bolt hiera for operations
- Clear pointers to control repo for current config
- Maintains minimal bootstrap capability for disaster recovery

#### 6.3 Update Bolt Puppetfile Comment

```bash
cat > Puppetfile <<'EOF'
# This Puppetfile is managed by Bolt. Do not edit.
# For more information, see https://pup.pt/bolt-modules
#
# NOTE: Puppet control repo Puppetfile is now separate
# This file contains only Bolt-specific modules for infrastructure provisioning

moduledir '.modules'

# Bolt modules for infrastructure provisioning
mod 'puppetlabs/complyadm', '3.5.0'
mod 'puppetlabs/cd4peadm', '5.11.0'
mod 'puppetlabs/peadm', '3.33.0'
mod 'puppetlabs/docker', '9.1.0'
mod 'puppetlabs/pkcs7', '0.1.2'
mod 'puppetlabs/yumrepo_core', '2.1.0'
mod 'puppetlabs/puppet_agent', '4.21.0'
mod 'puppetlabs/stdlib', '9.7.0'
mod 'puppetlabs/node_manager', '1.1.0'
mod 'puppet/format', '1.1.1'
mod 'puppetlabs/service', '3.1.0'
mod 'puppetlabs/package', '3.1.0'
mod 'puppetlabs/inifile', '6.2.0'
mod 'puppetlabs/ruby_task_helper', '1.0.0'
mod 'puppetlabs/apt', '9.4.0'
mod 'puppetlabs/powershell', '6.0.2'
mod 'puppetlabs/reboot', '5.1.0'
mod 'puppetlabs/facts', '1.7.0'
mod 'puppetlabs/pwshlib', '1.2.3'
EOF
```

#### 6.4 Update CLAUDE.md Documentation

Add section about control repo split:

```markdown
## Control Repo Architecture

**Separation:**
- `proxtoboltfu/` - Infrastructure provisioning (Tofu, Bolt, operational plans)
- `puppet-control-repo/` - Configuration management (Puppet code, roles, profiles)

**Control Repo Location:** `<git-repo-url>`

**Deployment:**
Control repo is deployed via Code Manager to PE environments:
- Branch `production` → environment `production`
- Branch `development` → environment `development`

**Workflow:**
1. Make changes to puppet-control-repo
2. Commit and push to appropriate branch
3. Deploy via Code Manager: `puppet-code deploy <environment>`
4. Agents receive updated catalog on next run

## Hiera Data Architecture

**Bootstrap vs Operations:**

After control repo split, hiera data serves different purposes in each repo:

**proxtoboltfu/data/** (Bootstrap only)
- Used during initial provisioning
- Minimal values needed to build infrastructure from scratch
- NOT used for day-2 operations
- Contains pointers to control repo for operational config

**puppet-control-repo/data/** (Source of truth)
- Used by Puppet agents via Code Manager
- All operational configuration lives here
- Updated via git workflow + Code Manager deployment
- Role-based hierarchy using trusted facts

**Day 2 Operations Pattern:**

Bolt maintenance/upgrade plans read current configuration from running infrastructure:

```puppet
# Upgrade plan reads live config from PE (which gets it from control repo)
$live_config = run_task('proxtoboltfu::get_pe_config', $targets)

# NOT from Bolt's potentially stale hiera
# $config = lookup('peadm::config')  # Don't use for operations
```

**Control repo is source of truth for:**
- Hostnames and network configuration
- Application passwords (dashboard, nessus)
- Console passwords
- Forge authorization tokens
- Code Manager credentials
- Agent platform repositories
- All ongoing operational configuration

**Bolt hiera contains only:**
- PE license key (for reprovisioning)
- Initial bootstrap topology
- Minimal disaster recovery data

See: `docs/control-repo-split.md` for detailed implementation.
```

#### 6.5 Commit Changes

```bash
git add -A
git commit -m "Remove control repo files (moved to puppet-control-repo)

Control repo files now live in separate repository:
<git-repo-url>

proxtoboltfu now contains only:
- Infrastructure provisioning (Tofu/Bolt)
- Bolt plans and tasks
- Operational hiera data

Maintains clean separation between infrastructure build
and configuration management"

git push
```

---

## Post-Split Architecture

### File Distribution

**proxtoboltfu/** (Infrastructure provisioning)
```
proxtoboltfu/
├── tf/                    # OpenTofu VM provisioning
├── plans/                 # Bolt orchestration plans
├── tasks/                 # Bolt tasks (inventory, etc)
├── data/                  # Operational data (PE config, SCM config)
├── keys/                  # Eyaml keys for operational secrets
├── hiera.yaml             # Bolt hiera config
├── Puppetfile             # Bolt modules only (.modules/)
├── inventory.yaml         # Dynamic inventory
└── bolt-project.yaml      # Bolt configuration
```

**puppet-control-repo/** (Configuration management)
```
puppet-control-repo/
├── manifests/
│   └── site.pp            # Node classification
├── site-modules/
│   ├── profile/           # Component configurations
│   └── role/              # Role definitions
├── data/                  # Hiera data for Puppet
├── modules/               # Forge modules (deployed by Code Manager)
├── scripts/               # Config version scripts
├── Puppetfile             # Puppet module dependencies
├── environment.conf       # Environment configuration
└── hiera.yaml             # Puppet hiera config
```

### Workflow Changes

**Before split:**
```
Developer → proxtoboltfu (everything) → Bolt runs → PE applies
```

**After split:**
```
# Infrastructure changes
Developer → proxtoboltfu → Tofu/Bolt → Provision infrastructure

# Configuration changes
Developer → puppet-control-repo → Git push → Code Manager → PE applies
```

### Benefits

1. **Clean separation:** Infrastructure vs configuration concerns
2. **Standard structure:** Control repo follows PE best practices
3. **No conflicts:** Separate Puppetfiles for Bolt vs PE
4. **Code Manager integration:** Proper deployment pipeline
5. **Independent versioning:** Infrastructure and config can evolve separately
6. **Team workflow:** Different teams can manage infrastructure vs configuration

### Maintenance Notes

**Module updates:**
- Bolt modules: Edit `proxtoboltfu/Puppetfile`, run `bolt module install`
- Puppet modules: Edit `puppet-control-repo/Puppetfile`, push, run `puppet-code deploy`

**Profile changes:**
- Edit in `puppet-control-repo/site-modules/profile/`
- Commit, push, deploy via Code Manager
- Test in development environment first

**Infrastructure changes:**
- Edit Terraform or Bolt plans in `proxtoboltfu/`
- Run `tofu apply` or `bolt plan run` as needed
- Does not affect control repo

---

## Phase 7: Day 2 Operations - Preventing Hiera Drift

### The Challenge

After the split, some configuration values are conceptually shared between repos:
- Hostnames (used in both bootstrap and ongoing operations)
- Credentials (initially set during build, rotated during operations)
- Version numbers (recorded at build, updated during upgrades)

**Risk:** Values drift over time as control repo is updated but Bolt's bootstrap hiera becomes stale.

**Impact:** 6 months later, you run an upgrade plan and it uses outdated credentials/hostnames from Bolt hiera → operation fails.

### Solution: Pull from Running Infrastructure

**Strategy:** Bolt day-2 operations read configuration from the running infrastructure (which uses control repo as source of truth), NOT from Bolt's hiera.

### 7.1 Create Configuration Extraction Task

```bash
# tasks/get_pe_config.sh
#!/bin/bash
# Extract current PE configuration from running infrastructure
# This reads the ACTUAL config (from control repo) not stale Bolt hiera

set -e

# Read from Puppet Server's actual configuration
console_password=$(puppet lookup peadm::config.console_password --render-as s 2>/dev/null || echo "")
forge_token=$(puppet lookup 'puppet_enterprise::master::code_manager::forge_settings.authorization_token' --render-as s 2>/dev/null || echo "")
r10k_remote=$(puppet config print r10k_remote --section master 2>/dev/null || echo "")

# Get PE version from running system
pe_version=$(puppet --version 2>/dev/null || echo "unknown")

# Return as JSON
cat <<EOF
{
  "console_password": "$console_password",
  "forge_authorization_token": "$forge_token",
  "r10k_remote": "$r10k_remote",
  "pe_version": "$pe_version"
}
EOF
```

```json
# tasks/get_pe_config.json
{
  "description": "Extract current PE configuration from running infrastructure",
  "parameters": {},
  "input_method": "stdin"
}
```

### 7.2 Update Upgrade Plans to Use Live Config

```puppet
# plans/upgrade_pe.pp
# Example: PE upgrade plan that reads from running infrastructure

plan proxtoboltfu::upgrade_pe(
  String $new_version,
  TargetSpec $targets = 'puppet-enterprise-nodes',
  Boolean $use_bolt_hiera = false,  # Emergency fallback only
) {

  if $use_bolt_hiera {
    # Fallback: use Bolt's hiera (may be stale)
    warning("WARNING: Using Bolt hiera - values may be outdated!")
    warning("Only use this if control repo/PE unavailable")
    $config = lookup('peadm::config')
  } else {
    # Primary path: read current state from running system
    out::message("Reading configuration from running PE infrastructure...")

    $live_config_result = run_task('proxtoboltfu::get_pe_config', $targets)

    unless $live_config_result.ok {
      fail_plan("Failed to read config from running infrastructure. Use use_bolt_hiera=true if PE is unavailable.")
    }

    $live_config = $live_config_result.first.value

    # Validate we got required values
    unless $live_config['console_password'] and $live_config['console_password'] != '' {
      fail_plan("Could not retrieve console password from running infrastructure")
    }

    $config = {
      'version' => $new_version,
      'primary_host' => $targets[0].name,
      'console_password' => $live_config['console_password'],
      'forge_authorization_token' => $live_config['forge_authorization_token'],
      'r10k_remote' => $live_config['r10k_remote'],
    }

    out::message("Using current configuration from control repo")
    out::message("  Console password: [redacted]")
    out::message("  Forge token: ${live_config['forge_authorization_token'][0,20]}...")
    out::message("  r10k remote: ${live_config['r10k_remote']}")
  }

  out::message("Upgrading PE from ${live_config['pe_version']} to ${new_version}...")

  run_plan('peadm::upgrade', $config)
}
```

**Apply same pattern to:**
- `plans/upgrade_scm.pp`
- `plans/upgrade_cd4pe.pp`
- `plans/add_compiler.pp`
- Any other day-2 operational plans

### 7.3 Create Optional Snapshot Plan

For disaster recovery preparedness, allow updating Bolt's hiera from current production state:

```puppet
# plans/snapshot_current_config.pp
plan proxtoboltfu::snapshot_current_config(
  TargetSpec $targets = 'puppet-enterprise-nodes',
  Boolean $confirm = false,
) {

  unless $confirm {
    fail_plan(@(END))
      This plan updates Bolt's bootstrap hiera with current production values.

      Use case: Disaster recovery preparation
      - Keeps Bolt's hiera reasonably current
      - Useful if you need to rebuild from scratch with recent values

      This is OPTIONAL and not required for normal operations.
      Day-2 plans always read from running infrastructure by default.

      Run with confirm=true to proceed.
      END
  }

  out::message("Extracting current configuration from running infrastructure...")

  $live_config = run_task('proxtoboltfu::get_pe_config', $targets).first.value

  out::message("Updating Bolt hiera with current values...")

  # Update data/pe.yaml with current values (keeping structure, updating values)
  # This is a snapshot for DR purposes, not used by day-2 operations

  out::message(@(END))
    Snapshot complete. Bolt's bootstrap hiera updated with current values.

    Updated:
    - PE version
    - Hostnames
    - Topology

    NOT updated (remain in control repo only):
    - Passwords
    - Tokens
    - Credentials

    Commit changes: git add data/ && git commit -m "Update bootstrap hiera snapshot"
    END
}
```

### 7.4 Document the Pattern

**Update plan documentation headers:**

```puppet
# plans/upgrade_pe.pp
# @summary Upgrade Puppet Enterprise to a new version
#
# @param new_version
#   Target PE version to upgrade to
#
# @param targets
#   PE infrastructure targets (default: puppet-enterprise-nodes)
#
# @param use_bolt_hiera
#   Emergency fallback: use Bolt's hiera instead of reading from infrastructure
#   Only use if PE is unavailable. Values may be stale.
#   Default: false (read from running infrastructure)
#
# @example Upgrade to new version (normal operation)
#   bolt plan run proxtoboltfu::upgrade_pe new_version=2025.7.0
#
# @example Upgrade using stale Bolt hiera (emergency only)
#   bolt plan run proxtoboltfu::upgrade_pe new_version=2025.7.0 use_bolt_hiera=true
```

### 7.5 Operational Procedures

**Normal day-2 operations:**
```bash
# Upgrade PE - reads current config from running infrastructure automatically
bolt plan run proxtoboltfu::upgrade_pe new_version=2025.7.0

# No hiera sync needed - plan reads from control repo via running PE
```

**Disaster recovery scenario:**
```bash
# If you need to rebuild from scratch and want recent-ish values
bolt plan run proxtoboltfu::snapshot_current_config confirm=true
git add data/ && git commit -m "Snapshot current config for DR"

# Then rebuild uses updated bootstrap values
bolt plan run proxtoboltfu::build_environment
```

**Emergency fallback (PE unavailable):**
```bash
# Only if running infrastructure is unavailable
# Uses potentially stale Bolt hiera
bolt plan run proxtoboltfu::upgrade_pe new_version=2025.7.0 use_bolt_hiera=true
```

### 7.6 Benefits of This Approach

**1. Eliminates drift as an operational problem**
- No synchronization required between repos
- Control repo remains single source of truth
- Day-2 operations always use current values

**2. Aligns with reality**
- Credentials rotate in control repo
- Upgrades automatically pick up rotated credentials
- No manual sync step to forget

**3. Maintains disaster recovery capability**
- Bolt's bootstrap hiera still exists for reprovisioning
- Optional snapshot plan for DR preparedness
- Emergency fallback if infrastructure unavailable

**4. Clear mental model**
- **Bootstrap:** Bolt hiera → Build infrastructure → Deploy control repo
- **Operations:** Control repo → Infrastructure → Bolt reads live config
- **Recovery:** Bolt hiera snapshot → Rebuild infrastructure

**5. Self-documenting**
- Plan parameters make the pattern explicit (`use_bolt_hiera=false`)
- Comments in Bolt hiera point to control repo
- Clear operational procedures

---

## Quick Reference

### Key Files and Locations

**proxtoboltfu/** (after split)
```
├── control-repo-template/    # Template for bootstrapping new control repos
├── data/                      # Bootstrap hiera (minimal, with pointers)
├── plans/                     # Bolt orchestration (reads from live infrastructure)
├── tasks/get_pe_config.sh     # Extracts config from running PE
└── Puppetfile                 # Bolt modules only (auto-generated)
```

**puppet-control-repo/**
```
├── data/
│   ├── roles/                 # Role-based hiera (source of truth)
│   ├── nodes/                 # Node-specific overrides
│   └── common.yaml            # Common defaults
├── manifests/site.pp          # Node classification
├── site-modules/              # Roles and profiles
└── Puppetfile                 # Puppet modules for agents
```

### Common Commands

**Initial deployment:**
```bash
bolt plan run proxtoboltfu::build_environment
```

**Deploy control repo changes:**
```bash
cd puppet-control-repo
git add . && git commit -m "Update config"
git push
puppet-code deploy production --wait
```

**Upgrade PE (reads from live infrastructure):**
```bash
bolt plan run proxtoboltfu::upgrade_pe new_version=2025.7.0
```

**Clean bootstrap hiera after deployment:**
```bash
bolt plan run proxtoboltfu::cleanup_bootstrap_hiera confirm=true
```

**Snapshot current config for DR:**
```bash
bolt plan run proxtoboltfu::snapshot_current_config confirm=true
```

### Data Flow

**Bootstrap (day 0):**
```
Bolt hiera → Provision → Deploy control repo → PE uses control repo
```

**Operations (day 2):**
```
Control repo → Code Manager → PE infrastructure → Bolt reads live config → Upgrades
```

**Disaster recovery:**
```
Bolt hiera snapshot → Rebuild infrastructure → Deploy control repo → Resume operations
```

### Hiera Hierarchy

**Control repo (puppet-control-repo/hiera.yaml):**
1. `data/nodes/{certname}.yaml` (highest priority)
2. `data/roles/{pp_role}.yaml` (from trusted extension)
3. `data/common.yaml` (lowest priority)

**Bolt repo (proxtoboltfu/hiera.yaml):**
Only used for initial provisioning, contains pointers to control repo for operational values.

---

## Validation Checklist

**Phase 1-2: Bootstrap and File Copy**
- [ ] Control repo cloned from puppetlabs template
- [ ] Template files copied from proxtoboltfu/control-repo-template/
- [ ] Role-based hiera structure created (data/roles/, data/nodes/)
- [ ] Hiera data migrated to role-specific files
- [ ] Puppetfile created with Puppet module dependencies only

**Phase 3: Git Setup**
- [ ] Git repository initialized and pushed to remote
- [ ] Production branch created and pushed
- [ ] Development branch created (optional)

**Phase 4: Code Manager**
- [ ] Deploy key generated on PE server
- [ ] Deploy key added to Git repository
- [ ] Code Manager configured in PE console (r10k_remote, r10k_private_key_file)
- [ ] RBAC token generated for Code Manager API
- [ ] `puppet agent -t` run on PE server to apply Code Manager config

**Phase 5: Deployment**
- [ ] `puppet-code deploy production --wait` runs successfully
- [ ] Environment directory created: `/etc/puppetlabs/code/environments/production/`
- [ ] Modules installed from Puppetfile in environment
- [ ] Site manifests and site-modules present
- [ ] Test agent receives catalog with role classification
- [ ] Agent Puppet run succeeds with role applied

**Phase 6: Cleanup**
- [ ] Control repo files moved to proxtoboltfu/control-repo-template/
- [ ] Bootstrap hiera cleaned (`cleanup_bootstrap_hiera` plan run)
- [ ] Bolt hiera files contain only bootstrap values with pointers
- [ ] CLAUDE.md updated with control repo architecture
- [ ] Changes committed to proxtoboltfu

**Phase 7: Day 2 Operations**
- [ ] `tasks/get_pe_config.sh` created and tested
- [ ] Upgrade plans updated to read from live infrastructure
- [ ] Optional snapshot plan created
- [ ] Plan documentation headers updated
- [ ] Operational procedures documented

---

## Rollback Plan

If issues occur:

1. **Control repo deployment fails:**
   - Check Code Manager logs: `/var/log/puppetlabs/puppetserver/code-manager.log`
   - Verify deploy key permissions
   - Test Git connectivity: `sudo -u pe-puppet git ls-remote <repo-url>`

2. **Agent catalogs fail to compile:**
   - Check Puppet Server logs: `/var/log/puppetlabs/puppetserver/puppetserver.log`
   - Verify module dependencies in Puppetfile
   - Test catalog compilation: `puppet catalog compile <node-name>`

3. **Complete rollback:**
   - Original control repo files still in proxtoboltfu git history
   - Revert commits and restore files if needed
   - Disable Code Manager and use environment directory directly

---

## Future Enhancements

**After successful split:**

1. **Webhook deployment:** Configure Git webhooks to trigger Code Manager deployments automatically
2. **CD4PE integration:** Use CD4PE for testing and deployment pipelines
3. **Branch protection:** Require PR reviews before merging to production
4. **Automated testing:** Add rspec-puppet tests for roles and profiles
5. **Impact analysis:** Use PE Impact Analysis before deploying changes
