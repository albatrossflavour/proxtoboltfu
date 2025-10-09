#!/bin/bash
# Initialize Terraform with backend configuration

set -euo pipefail

# Parse parameters
terraform_dir="${PT_terraform_dir:-tf}"

cd "$terraform_dir" || exit 1

# Initialize Terraform
echo "Initializing Terraform in $terraform_dir"
tofu init

echo "Terraform initialization completed successfully"
