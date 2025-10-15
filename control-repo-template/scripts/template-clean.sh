#!/bin/sh

# Template cleanup script - destroys Linux templates but preserves Windows templates
# Keeps manually managed Terraform configuration files

echo "Cleaning up Linux templates (preserving Windows templates)..."

# Get all template IDs except Windows (91000+)
TEMPLATES_TO_DESTROY=$(qm list | grep template | awk '$1 < 91000 {print $1}')

if [ -z "$TEMPLATES_TO_DESTROY" ]; then
	echo "No Linux templates found to destroy."
else
	echo "Found templates to destroy: $TEMPLATES_TO_DESTROY"
	echo "Destroying templates..."

	for template_id in $TEMPLATES_TO_DESTROY; do
		echo "Destroying template $template_id..."
		if qm destroy "$template_id" --destroy-unreferenced-disks 1 --purge 2>/dev/null; then
			echo "✓ Successfully destroyed template $template_id"
		else
			echo "✗ Failed to destroy template $template_id"
			# Try alternative cleanup for stuck templates
			echo "  Attempting alternative cleanup..."
			qm template "$template_id" --disk scsi0 2>/dev/null || true
			qm destroy "$template_id" --purge 2>/dev/null || echo "  Manual cleanup may be required"
		fi
	done
fi

echo "Template cleanup completed!"
echo ""
echo "Run './template-generate.sh' to recreate templates with consistent numbering."
