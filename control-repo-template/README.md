# Control Repo Template

This directory contains template files for bootstrapping the Puppet control repository.

## Files

- `Puppetfile` - Puppet modules for agent configuration (excludes Bolt-specific modules)
- `hiera.yaml` - Hiera configuration with absolute paths to eyaml keys
- `data/` - Role-based hiera data structure (created by bootstrap plan)

## Key Differences from igor

### Puppetfile

**igor/Puppetfile:**

- Contains Bolt modules (peadm, complyadm, cd4peadm)
- Installed to `.modules/`
- Used for infrastructure provisioning

**control-repo-template/Puppetfile:**

- Contains Puppet modules for agent configuration
- Deployed by Code Manager to `/etc/puppetlabs/code/environments/`
- Used for ongoing configuration management

### hiera.yaml

**igor/hiera.yaml:**

- Relative paths: `keys/private_key.pkcs7.pem`
- Used by Bolt from local checkout

**control-repo-template/hiera.yaml:**

- Absolute paths: `/etc/puppetlabs/secure/keys/private_key.pkcs7.pem`
- Used by Puppet Server after Code Manager deployment
- Keys already present on PE server (deployed during build_pe)

## Usage

The `bootstrap_control_repo` plan automatically uses these templates:

```bash
bolt plan run igor::bootstrap_control_repo
```

This creates a new control repo at `~/dev/puppet-control-repo` with:

- Template files from this directory
- manifests/site-modules/scripts from igor
- Role-based data structure

## Manual Updates

To update the control repo template:

1. Edit files in `control-repo-template/`
2. Run `bootstrap_control_repo` plan to regenerate control repo
3. Or manually copy updated files to existing control repo

## See Also

- `docs/control-repo-split.md` - Full implementation plan
- `plans/bootstrap_control_repo.pp` - Automation plan
