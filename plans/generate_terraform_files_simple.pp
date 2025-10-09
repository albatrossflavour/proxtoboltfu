# @summary Simple Terraform template configuration file generator
# @param template_data Comma-separated data from Proxmox qm list (vmid,name,status)
# @param storage Storage backend used for templates (default: ceph)
plan proxtoboltfu::generate_terraform_files_simple (
  String $template_data,
  String $storage = 'ceph'
) {

  out::message("📝 Generating Terraform template configuration files (simple version)")
  out::message("Storage: ${storage}")
  out::message("Template data: ${template_data}")

  # Generate a basic Terraform file
  $terraform_content = @("TERRAFORM_FILE")
    # Generated automatically by proxtoboltfu::generate_terraform_files_simple
    # DO NOT EDIT MANUALLY - this file is regenerated when templates change
    
    locals {
      # VM template IDs from Proxmox
      # Update these based on actual template creation results
      vm_templates = {
        alma8 = {
          template_id   = 11101
          template_name = "template-Alma-8"
          os_family     = "alma" 
          os_version    = "8"
          storage       = "${storage}"
        }
        ubuntu2404 = {
          template_id   = 12401
          template_name = "template-Ubuntu-2404"
          os_family     = "ubuntu"
          os_version    = "2404" 
          storage       = "${storage}"
        }
      }
      
      # Helper maps for easier reference
      template_ids = {
        for k, v in local.vm_templates : k => v.template_id
      }
      
      template_names = {
        for k, v in local.vm_templates : k => v.template_name
      }
    }
    | TERRAFORM_FILE

  # Write the generated Terraform file
  $terraform_file = 'tf/generated_templates.tf'
  
  out::message("💾 Writing Terraform configuration to ${terraform_file}")
  file::write($terraform_file, $terraform_content)

  out::message("✅ Simple Terraform template file generated successfully")

  return { 
    status => 'completed',
    terraform_file => $terraform_file
  }
}