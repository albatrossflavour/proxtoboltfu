resource "proxmox_vm_qemu" "nessus-server" {
  count        = var.nessus ? 1 : 0
  vmid         = "995"
  target_nodes = ["ankh", "morpork"]
  tags         = "puppetinfra;nessus;prod;ubuntu"
  description  = "Nessus security scanner server"
  onboot       = true
  #hastate                = "started"
  agent                  = 1
  qemu_os                = "l26"
  agent_timeout          = 600
  clone                  = "template-Ubuntu-2404"
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
  memory = 4096
  name   = "new-nessus.${var.domain}"
  #protection = true
  bootdisk   = "scsi0"
  scsihw     = "virtio-scsi-single"
  ipconfig0  = "ip=192.168.10.104/24,gw=192.168.10.1"
  nameserver = "192.168.9.2 192.168.9.3"
  ciuser     = var.ciuser
  cipassword = var.cipassword
  sshkeys    = var.sshkey

  network {
    id     = 0
    bridge = "vmbr1"
    model  = "virtio"
    tag    = 6
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

resource "pihole_dns_record" "new-nessus" {
  count  = var.nessus ? 1 : 0
  domain = "new-nessus.${var.domain}"
  ip     = regexall("ip=([^/]+)", proxmox_vm_qemu.nessus-server[0].ipconfig0)[0][0]
}
