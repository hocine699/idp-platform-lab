locals {
  nodes = {
    "k8s-cp-01"     = { vm_id = 110, ip = "192.168.1.70", cores = 2, memory = 4096, node = "pve01", template = 9000 }
    "k8s-worker-01" = { vm_id = 120, ip = "192.168.1.71", cores = 2, memory = 6144, node = "pve01", template = 9000 }
    "k8s-worker-02" = { vm_id = 121, ip = "192.168.1.72", cores = 2, memory = 6144, node = "pve01", template = 9000 }
    "k8s-worker-03" = { vm_id = 122, ip = "192.168.1.73", cores = 4, memory = 8192, node = "pve02", template = 9001 }
    "k8s-worker-04" = { vm_id = 123, ip = "192.168.1.74", cores = 4, memory = 8192, node = "pve02", template = 9001 }
  }
}

resource "proxmox_virtual_environment_vm" "k8s" {
  for_each = local.nodes

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vm_id

  clone {
    vm_id = each.value.template
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
      servers = ["192.168.1.253", "9.9.9.9"]
    }

    user_account {
      username = "hocine"
      keys     = [file("~/.ssh/id_ed25519.pub")]
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account]
  }

  agent {
    enabled = true
  }
}
