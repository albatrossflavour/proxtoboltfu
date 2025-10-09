terraform {
  required_version = "v1.10.6"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
    pihole = {
      source  = "ryanwholey/pihole"
      version = "2.0.0-beta.1"
    }
  }
  backend "s3" {}
}

provider "proxmox" {
  pm_api_url                  = var.api_url
  pm_api_token_id             = var.proxmox_token_id
  pm_api_token_secret         = var.proxmox_token_secret
  pm_tls_insecure             = true
  pm_log_enable               = false
  pm_log_file                 = "terraform-plugin-proxmox.log"
  pm_debug                    = false
  pm_minimum_permission_check = false
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}

provider "pihole" {
  url      = "http://pihole.${var.domain}"
  password = var.pihole_password
}
