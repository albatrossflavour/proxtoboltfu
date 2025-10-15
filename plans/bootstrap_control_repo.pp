# @summary Bootstrap puppet control repo from template
# @param work_dir Directory to clone template into (default: ~/dev)
# @param push Whether to push to remote after initial commit (default: false)
# @param overwrite Whether to remove existing directory if it exists (default: false)
plan proxtoboltfu::bootstrap_control_repo (
  String $work_dir = '~/dev',
  Boolean $push = false,
  Boolean $overwrite = false
) {

  out::message("=== Bootstrapping Puppet Control Repo ===")
  out::message("")

  # Lookup configuration from hiera
  $github_username = lookup('pe_github_username', String, first, undef)
  $control_repo_name = lookup('pe_control_repo_name', String, first, undef)

  unless $github_username and $control_repo_name {
    fail_plan("github_username and control_repo_name must be set in peadm::config")
  }

  $repo_url = "git@github.com:${github_username}/${control_repo_name}.git"
  $repo_path = "${work_dir}/${control_repo_name}"

  out::message("Configuration:")
  out::message("  GitHub user: ${github_username}")
  out::message("  Repo name: ${control_repo_name}")
  out::message("  Repo URL: ${repo_url}")
  out::message("  Local path: ${repo_path}")
  out::message("")

  # Check if directory already exists FIRST
  $check_dir = run_command(
    "test -d ${repo_path} && echo 'exists' || echo 'not found'",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $check_dir.ok {
    $dir_status = $check_dir.first.value['stdout'].strip

    if $dir_status == 'exists' {
      unless $overwrite {
        fail_plan(@(END))
          Directory already exists: ${repo_path}

          This directory may contain uncommitted work.
          To remove it and start fresh, run with overwrite=true:

            bolt plan run proxtoboltfu::bootstrap_control_repo overwrite=true

          Or manually remove it first:

            rm -rf ${repo_path}
          END
      }

      out::message("⚠ Directory exists, removing (overwrite=true)...")
    }
  }

  # Create GitHub repository if it doesn't exist
  out::message("Checking GitHub repository...")

  $gh_check = run_command(
    "gh repo view ${github_username}/${control_repo_name} --json name 2>&1",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $gh_check.ok {
    out::message("✓ GitHub repository already exists")
  } else {
    out::message("  Creating GitHub repository...")

    $gh_create = run_command(
      "gh repo create ${github_username}/${control_repo_name} --private --description 'Puppet control repository'",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    unless $gh_create.ok {
      fail_plan(@(END))
        Failed to create GitHub repository

        Error: ${gh_create.first.error}

        Make sure:
        1. GitHub CLI (gh) is installed and authenticated
           Install: brew install gh
           Login: gh auth login

        2. You have permission to create repositories

        Or create manually:
          gh repo create ${github_username}/${control_repo_name} --private
        END
    }

    out::message("✓ GitHub repository created")
  }

  out::message("")

  # Phase 1: Clone template and setup git
  out::message("Phase 1: Cloning puppetlabs control-repo template...")

  if $overwrite {
    $remove_cmd = "rm -rf ${control_repo_name} && "
  } else {
    $remove_cmd = ''
  }

  $clone_cmd = @("EOT")
    cd ${work_dir} && \
    ${remove_cmd}git clone https://github.com/puppetlabs/control-repo.git ${control_repo_name} && \
    cd ${control_repo_name} && \
    rm -rf .git && \
    git init && \
    git remote add origin ${repo_url}
    | EOT

  $clone_result = run_command(
    $clone_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $clone_result.ok {
    fail_plan("Failed to clone template: ${clone_result.first.error}")
  }

  out::message("✓ Template cloned and git initialized")
  out::message("")

  # Phase 2: Copy files and create structure
  out::message("Phase 2: Copying files from proxtoboltfu...")

  # Copy manifests, site-modules, scripts
  $copy_cmd = @("EOT")
    cd ${work_dir}/${control_repo_name} && \
    rm -rf manifests site-modules scripts environment.conf && \
    cp -r ${work_dir}/proxtoboltfu/control-repo-template/manifests . && \
    cp -r ${work_dir}/proxtoboltfu/control-repo-template/site-modules . && \
    cp -r ${work_dir}/proxtoboltfu/control-repo-template/scripts . && \
    cp ${work_dir}/proxtoboltfu/control-repo-template/environment.conf .
    | EOT

  $copy_result = run_command(
    $copy_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $copy_result.ok {
    fail_plan("Failed to copy files from template: ${copy_result.first.error}")
  }

  out::message("✓ Template files copied (manifests, site-modules, scripts, environment.conf)")

  # Copy template files (hiera.yaml, Puppetfile)
  out::message("  Copying template files...")

  $template_cmd = @("EOT")
    cd ${repo_path} && \
    cp ${work_dir}/proxtoboltfu/control-repo-template/hiera.yaml . && \
    cp ${work_dir}/proxtoboltfu/control-repo-template/Puppetfile .
    | EOT

  $template_result = run_command(
    $template_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $template_result.ok {
    fail_plan("Failed to copy template files: ${template_result.first.error}")
  }

  out::message("✓ Template files copied (hiera.yaml, Puppetfile)")

  # Copy actual data files from proxtoboltfu (with generated values)
  out::message("  Copying hiera data with current values...")

  $data_cmd = @("EOT")
    cd ${repo_path} && \
    rm -rf data && \
    mkdir -p data/roles data/nodes data/os && \
    cp ${work_dir}/proxtoboltfu/data/common.yaml data/ && \
    cp ${work_dir}/proxtoboltfu/data/roles/*.yaml data/roles/ 2>/dev/null || true && \
    cp ${work_dir}/proxtoboltfu/data/os/*.yaml data/os/ 2>/dev/null || true && \
    touch data/nodes/.gitkeep
    | EOT

  $data_result = run_command(
    $data_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $data_result.ok {
    fail_plan("Failed to copy hiera data: ${data_result.first.error}")
  }

  out::message("✓ Hiera data copied (common.yaml, roles/*.yaml, os/*.yaml)")
  out::message("")

  # Phase 3: Initial commit
  out::message("Phase 3: Creating initial commit...")

  $commit_msg = @(EOT)
    Initial control repo

    Bootstrapped from puppetlabs/control-repo template
    Copied production code from proxtoboltfu:
    - manifests/site.pp (role-based classification)
    - site-modules/profile (infrastructure profiles)
    - site-modules/role (role definitions)
    - environment.conf and scripts/

    Puppetfile configured for required Forge modules
    Hiera configured with role-based hierarchy

    🤖 Generated with [Claude Code](https://claude.com/claude-code)

    Co-Authored-By: Claude <noreply@anthropic.com>
    | EOT

  $commit_cmd = @("EOT")
    cd ${repo_path} && \
    git add . && \
    git commit -m "$(cat <<'HEREDOC'
    ${commit_msg}
    HEREDOC
    )"
    | EOT

  $commit_result = run_command(
    $commit_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $commit_result.ok {
    fail_plan("Failed to commit: ${commit_result.first.error}")
  }

  out::message("✓ Initial commit created")

  # Create production and development branches
  $branch_cmd = @("EOT")
    cd ${repo_path} && \
    git checkout -b production && \
    git branch -D main || true && \
    git checkout -b development && \
    git checkout production
    | EOT

  $branch_result = run_command(
    $branch_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $branch_result.ok {
    fail_plan("Failed to create branches: ${branch_result.first.error}")
  }

  out::message("✓ Production and development branches created")
  out::message("")

  # Push if requested
  if $push {
    out::message("Pushing branches to remote...")

    $push_cmd = "cd ${repo_path} && git push -u origin production development"

    $push_result = run_command(
      $push_cmd,
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    unless $push_result.ok {
      $error_msg = $push_result.first.value['stderr']
      fail_plan(@(END))
        Failed to push to ${repo_url}

        Error: ${error_msg}

        Make sure:
        1. The GitHub repository exists: https://github.com/${github_username}/${control_repo_name}
           Create it with: gh repo create ${github_username}/${control_repo_name} --private

        2. SSH key is configured for GitHub access
           Test with: ssh -T git@github.com

        3. You have push access to the repository

        To push manually after fixing:
          cd ${repo_path}
          git push -u origin production development
        END
    }

    out::message("✓ Pushed production and development branches to ${repo_url}")
    out::message("")
  }

  out::message("=== Control Repo Bootstrap Complete ===")
  out::message("")
  out::message("Next steps:")
  out::message("  1. Migrate hiera data to data/roles/ using migrate_hiera_to_roles plan")
  out::message("  2. Review and update Puppetfile if needed")
  out::message("  3. Configure Code Manager in PE")
  out::message("  4. Deploy with: puppet-code deploy production --wait")
  out::message("")
  out::message("Control repo location: ${repo_path}")

  return {
    status => 'completed',
    repo_path => $repo_path,
    repo_url => $repo_url,
    pushed => $push
  }
}
