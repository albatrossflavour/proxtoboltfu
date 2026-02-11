# @summary Bootstrap puppet control repo from template
# @param work_dir Directory to clone template into (default: ~/dev)
# @param push Whether to push to remote after initial commit (default: false)
# @param overwrite Whether to remove existing directory if it exists (default: false)
plan igor::bootstrap_control_repo (
  String $work_dir = '~/dev',
  Boolean $push = false,
  Boolean $overwrite = false
) {

  out::message("=== Bootstrapping Puppet Control Repo ===")
  out::message("")

  # Lookup r10k remote from hiera
  $pe_params = lookup('peadm::config', Hash, first, undef)
  $repo_url = $pe_params['r10k_remote']

  unless $repo_url {
    fail_plan("r10k_remote must be set in peadm::config")
  }

  # Extract repo name from git URL (e.g., git@github.com:user/repo.git -> repo)
  $url_parts = split($repo_url, '/')
  $repo_name_with_ext = $url_parts[-1]
  $control_repo_name = regsubst($repo_name_with_ext, '\.git$', '')
  $repo_path = "${work_dir}/${control_repo_name}"

  # Extract GitHub username for repo creation
  $github_username = regsubst($repo_url, '^git@github\.com:([^/]+)/.*$', '\1')

  $project_root = system::env('PWD')

  out::message("Configuration:")
  out::message("  Repo URL: ${repo_url}")
  out::message("  Repo name: ${control_repo_name}")
  out::message("  GitHub user: ${github_username}")
  out::message("  Local path: ${repo_path}")
  out::message("")

  # Check if directory already exists
  $check_dir = run_command(
    "test -d ${repo_path} && echo 'exists' || echo 'not found'",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  $dir_exists = $check_dir.ok and $check_dir.first.value['stdout'].strip == 'exists'

  if $dir_exists {
    # Check if the existing directory has the correct git remote
    $remote_check = run_command(
      "cd ${repo_path} && git remote get-url origin 2>/dev/null || echo 'no-remote'",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    $current_remote = $remote_check.first.value['stdout'].strip

    if $current_remote == $repo_url {
      # Correct remote — do an idempotent update
      out::message("Directory exists with correct remote, updating...")

      # Ensure we're on production branch
      run_command(
        "cd ${repo_path} && git checkout production",
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      # Pull latest
      $pull_result = run_command(
        "cd ${repo_path} && git pull origin production",
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      unless $pull_result.ok {
        out::message("⚠ Pull failed, continuing with local copy...")
      }

      # Copy updated files from igor
      out::message("  Copying updated files from igor...")

      $update_cmd = @("EOT")
        cd ${repo_path} && \
        cp -r ${project_root}/control-repo-template/manifests/* manifests/ 2>/dev/null || true && \
        cp -r ${project_root}/control-repo-template/site-modules/* site-modules/ 2>/dev/null || true && \
        cp -r ${project_root}/control-repo-template/scripts/* scripts/ 2>/dev/null || true && \
        cp ${project_root}/control-repo-template/environment.conf . && \
        cp ${project_root}/control-repo-template/hiera.yaml . && \
        cp ${project_root}/control-repo-template/Puppetfile . && \
        cp ${project_root}/data/common.yaml data/ && \
        cp ${project_root}/data/roles/*.yaml data/roles/ 2>/dev/null || true && \
        cp ${project_root}/data/os/*.yaml data/os/ 2>/dev/null || true
        | EOT

      $update_result = run_command(
        $update_cmd,
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      unless $update_result.ok {
        fail_plan("Failed to copy updated files: ${update_result.first.error}")
      }

      # Check if there are changes to commit
      $diff_check = run_command(
        "cd ${repo_path} && git diff --quiet && git diff --cached --quiet",
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      if $diff_check.ok {
        out::message("✓ No changes detected, control repo is up to date")
      } else {
        out::message("  Changes detected, committing...")

        $commit_update = run_command(
          "cd ${repo_path} && git add -A && git commit -m 'Update control repo from igor'",
          'localhost',
          '_run_as' => system::env('USER'),
          '_catch_errors' => true
        )

        unless $commit_update.ok {
          fail_plan("Failed to commit updates: ${commit_update.first.error}")
        }

        if $push {
          $push_update = run_command(
            "cd ${repo_path} && git push origin production",
            'localhost',
            '_run_as' => system::env('USER'),
            '_catch_errors' => true
          )

          unless $push_update.ok {
            fail_plan("Failed to push updates: ${push_update.first.error}")
          }

          out::message("✓ Updates committed and pushed")
        } else {
          out::message("✓ Updates committed (push=false, not pushed)")
        }
      }

      return({
        status => 'updated',
        repo_path => $repo_path,
        repo_url => $repo_url,
        pushed => $push
      })
    } else {
      # Wrong remote or no remote
      unless $overwrite {
        fail_plan(@(END))
          Directory already exists with different remote: ${repo_path}
          Current remote: ${current_remote}
          Expected remote: ${repo_url}

          To remove it and start fresh, run with overwrite=true:

            bolt plan run igor::bootstrap_control_repo overwrite=true push=true

          Or manually remove it first:

            rm -rf ${repo_path}
          END
      }

      out::message("⚠ Directory exists with wrong remote, removing (overwrite=true)...")
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
  out::message("Phase 2: Copying files from igor...")

  # Copy manifests, site-modules, scripts
  $copy_cmd = @("EOT")
    cd ${work_dir}/${control_repo_name} && \
    rm -rf manifests site-modules scripts environment.conf && \
    cp -r ${project_root}/control-repo-template/manifests . && \
    cp -r ${project_root}/control-repo-template/site-modules . && \
    cp -r ${project_root}/control-repo-template/scripts . && \
    cp ${project_root}/control-repo-template/environment.conf .
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
    cp ${project_root}/control-repo-template/hiera.yaml . && \
    cp ${project_root}/control-repo-template/Puppetfile .
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

  # Copy actual data files from igor (with generated values)
  out::message("  Copying hiera data with current values...")

  $data_cmd = @("EOT")
    cd ${repo_path} && \
    rm -rf data && \
    mkdir -p data/roles data/nodes data/os && \
    cp ${project_root}/data/common.yaml data/ && \
    cp ${project_root}/data/roles/*.yaml data/roles/ 2>/dev/null || true && \
    cp ${project_root}/data/os/*.yaml data/os/ 2>/dev/null || true && \
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
    Copied production code from igor:
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
  out::message("Control repo location: ${repo_path}")

  return({
    status => 'completed',
    repo_path => $repo_path,
    repo_url => $repo_url,
    pushed => $push
  })
}
