resource "proxmox_vm_qemu" "new-scm-server" {
  count                  = var.puppet_scm ? 1 : 0
  vmid                   = "998"
  target_nodes           = ["ankh", "morpork"]
  tags                   = "puppetinfra;scm;prod;ubuntu"
  description            = "Puppet SCM server"
  onboot                 = true
  #hastate                = "started"
  agent                  = 1
  qemu_os                = "l26"
  agent_timeout          = 600
  clone                  = "template-Ubuntu-2204"
  full_clone             = false
  define_connection_info = false
  os_type                = "cloud-init"
  pool                   = "Puppet"
  cpu {
    type    = "host"
    cores   = 4
    sockets = 2
    numa    = false
  }
  memory     = 8192
  name       = "new-scm.${var.domain}"
  #protection = true
  bootdisk   = "scsi0"
  scsihw     = "virtio-scsi-single"
  ipconfig0  = "ip=192.168.7.101/24,gw=192.168.7.1,nameserver=192.168.9.2 192.168.9.3"
  ciuser     = var.ciuser
  cipassword = var.cipassword
  sshkeys    = var.sshkey

  network {
    id     = 0
    bridge = "vmbr1"
    model  = "virtio"
    tag    = 7
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage    = "ceph"
          size       = 50
          asyncio    = "threads"
          cache      = "writeback"
          discard    = true
          emulatessd = true
          iothread   = true

        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "ceph"
        }
      }
    }
  }

  depends_on = [proxmox_vm_qemu.new-puppet-server[0]]

  lifecycle {
    ignore_changes = [
      clone,
      clone_wait,
      full_clone,
      target_nodes,
      pool
    ]
  }
}

resource "pihole_dns_record" "new-scm" {
  count  = var.puppet_scm ? 1 : 0
  domain = "new-scm.${var.domain}"
  ip     = regexall("ip=([^/]+)", proxmox_vm_qemu.new-scm-server[0].ipconfig0)[0][0]
}
