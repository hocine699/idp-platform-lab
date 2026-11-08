# VM Windows ponctuelle : mises à jour des jouets VTech (Explor@ Park).
# Éteinte par défaut, à démarrer seulement quand on en a besoin.

resource "proxmox_hardware_mapping_usb" "globe" {
  name    = "vtech-globe"
  comment = "Globe VTech"
  map = [
    { id = "0f88:041e", node = "pve01", path = "1-2.2" },
  ]
}

resource "proxmox_virtual_environment_vm" "windows" {
  name            = "win11"
  node_name       = "pve01"
  vm_id           = 300
  description     = "Windows 11 ponctuel (VTech). Disque SATA + réseau e1000e : aucun pilote à charger."
  on_boot         = false
  keyboard_layout = "fr"

  bios    = "ovmf"
  machine = "pc-q35-11.0+pve2"
  operating_system {
    type = "win11"
  }

  cpu {
    cores = 4
    type  = "host"
  }
  memory {
    dedicated = 4096
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = true
  }
  tpm_state {
    datastore_id = "local-lvm"
    version      = "v2.0"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "sata0"
    size         = 64
  }
  cdrom {
    file_id   = "local:iso/Win11_fr_x64.iso"
    interface = "ide2"
  }
  boot_order = ["sata0", "ide2"]

  network_device {
    bridge = "vmbr0"
    model  = "e1000e"
  }


  agent {
    enabled = false
  }
}
