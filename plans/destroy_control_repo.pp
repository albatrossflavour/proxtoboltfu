# @summary Destroy control repo (delete GitHub repo and local directory)
# @param work_dir Directory containing control repo (default: ~/dev)
# @param confirm Whether to actually delete (default: false - dry run)
plan igor::destroy_control_repo (
  String $work_dir = '~/dev',
  Boolean $confirm = false
) {

  out::message("=== Destroying Control Repo ===")
  out::message("")

  # Lookup r10k remote from hiera
  $pe_params = lookup('peadm::config', Hash, first, undef)
  $repo_url = $pe_params['r10k_remote']

  unless $repo_url {
    fail_plan("r10k_remote must be set in peadm::config")
  }

  # Extract repo name from git URL
  $url_parts = split($repo_url, '/')
  $repo_name_with_ext = $url_parts[-1]
  $control_repo_name = regsubst($repo_name_with_ext, '\.git$', '')
  $repo_path = "${work_dir}/${control_repo_name}"

  # Extract GitHub username
  $github_username = regsubst($repo_url, '^git@github\.com:([^/]+)/.*$', '\1')

  out::message("Configuration:")
  out::message("  Repo URL: ${repo_url}")
  out::message("  Repo name: ${control_repo_name}")
  out::message("  GitHub user: ${github_username}")
  out::message("  Local path: ${repo_path}")
  out::message("")

  unless $confirm {
    out::message("⚠ DRY RUN MODE - Nothing will be deleted")
    out::message("")
    out::message("This will:")
    out::message("  1. Delete GitHub repository: ${github_username}/${control_repo_name}")
    out::message("  2. Delete local directory: ${repo_path}")
    out::message("")
    out::message("To actually delete, run with confirm=true:")
    out::message("  bolt plan run igor::destroy_control_repo confirm=true")
    out::message("")

    return({
      status => 'dry_run',
      repo_url => $repo_url,
      local_path => $repo_path
    })
  }

  out::message("⚠ CONFIRM=TRUE - Deleting control repo resources")
  out::message("")

  # Check if local directory exists
  $check_dir = run_command(
    "test -d ${repo_path} && echo 'exists' || echo 'not found'",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $check_dir.ok and $check_dir.first.value['stdout'].strip == 'exists' {
    out::message("Deleting local directory: ${repo_path}")

    $rm_dir = run_command(
      "rm -rf ${repo_path}",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    unless $rm_dir.ok {
      fail_plan("Failed to delete local directory: ${rm_dir.first.error}")
    }

    out::message("✓ Local directory deleted")
  } else {
    out::message("⊘ Local directory not found: ${repo_path}")
  }

  # Check if GitHub repo exists
  $gh_check = run_command(
    "gh repo view ${github_username}/${control_repo_name} --json name 2>&1",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $gh_check.ok {
    out::message("Deleting GitHub repository: ${github_username}/${control_repo_name}")

    $gh_delete = run_command(
      "gh repo delete ${github_username}/${control_repo_name} --yes",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )

    unless $gh_delete.ok {
      fail_plan("Failed to delete GitHub repository: ${gh_delete.first.error}")
    }

    out::message("✓ GitHub repository deleted")
  } else {
    out::message("⊘ GitHub repository not found: ${github_username}/${control_repo_name}")
  }

  out::message("")
  out::message("=== Control Repo Destroyed ===")

  return({
    status => 'completed',
    repo_url => $repo_url,
    local_path => $repo_path
  })
}
