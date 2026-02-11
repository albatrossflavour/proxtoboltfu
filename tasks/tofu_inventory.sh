#!/bin/bash
set -e

provider="${PT_provider:-proxmox}"
provider_dir="tf/providers/${provider}"

if [ ! -d "$provider_dir" ]; then
	echo '{"value": []}'
	exit 0
fi

inventory=$(cd "$provider_dir" && tofu output -json bolt_inventory 2>/dev/null || echo '[]')

if [ -n "$PT_tag_filter" ]; then
	inventory=$(echo "$inventory" | jq --arg tag "$PT_tag_filter" \
		'[.[] | select(.tags | split(";") | index($tag))]')
fi

echo "$inventory" | jq '{value: [.[] | {name, uri, vars: {tags}}]}'
