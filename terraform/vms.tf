locals {
  nodes = {
    "k8s-cp-01"     = { vm_id = 110, ip = "192.168.1.70", cores = 2, memory = 4096 }
    "k8s-worker-01" = { vm_id = 120, ip = "192.168.1.71", cores = 2, memory = 6144 }
    "k8s-worker-02" = { vm_id = 121, ip = "192.168.1.72", cores = 2, memory = 6144 }
  }
}

resource "proxmox_virtual_environment_vm" "k8s" {
  for_each = local.nodes

  name      = each.key
  node_name = "pve01"
  vm_id     = each.value.vm_id

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.1.1"
      }
    }

    dns {
      servers = ["9.9.9.9"]
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