#!/bin/bash
set -e

# Change to the terraform directory if provided
cd "${PT_dir:-.}" || exit 1

# Get all proxmox_vm_qemu resources from state
resources=$(tofu state list 2>/dev/null | grep '^proxmox_vm_qemu\.' || echo "")

if [ -z "$resources" ]; then
  # Return empty targets array if no resources exist
  echo '{"value": []}'
  exit 0
fi

# Build JSON array of targets
targets="["
first=true

for resource in $resources; do
  # Get the VM name, IP, and tags
  state=$(tofu state show "$resource" 2>/dev/null || echo "")
  if [ -z "$state" ]; then
    continue
  fi

  name=$(echo "$state" | grep -E '^\s+name\s+=' | sed -n 's/.*= "\(.*\)"/\1/p')
  ip=$(echo "$state" | grep ipconfig0 | sed -n 's/.*ip=\([^/]*\).*/\1/p')
  tags=$(echo "$state" | grep -E '^\s+tags\s+=' | sed -n 's/.*= "\(.*\)"/\1/p')

  # Apply tag filter if specified
  if [ -n "$PT_tag_filter" ]; then
    # Include only if tag is present (match whole tag, not substring)
    # Tags are semicolon-separated, so match with boundaries
    if [ -z "$tags" ] || ! echo "$tags" | grep -qE "(^|;)${PT_tag_filter}(;|$)"; then
      continue
    fi
  fi

  if [ -n "$name" ] && [ -n "$ip" ]; then
    if [ "$first" = false ]; then
      targets="$targets,"
    fi

    # Build target with tags in vars
    if [ -n "$tags" ]; then
      targets="$targets{\"name\":\"${name}\",\"uri\":\"$ip\",\"vars\":{\"tags\":\"$tags\"}}"
    else
      targets="$targets{\"name\":\"${name}\",\"uri\":\"$ip\"}"
    fi
    first=false
  fi
done

targets="$targets]"

# Return in the format expected by Bolt's task plugin
cat <<EOF
{"value": $targets}
EOF
