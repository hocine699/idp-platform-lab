resource "proxmox_virtual_environment_vm" "test" {
  name      = "vm-test"
  node_name = "pve01"
  vm_id     = 101

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.61/24"
        gateway = "192.168.1.1"
      }
    }

    user_account {
      username = "hocine"
      keys     = [file("~/.ssh/id_ed25519.pub")]
    }
  }

  agent {
    enabled = true
  }
}