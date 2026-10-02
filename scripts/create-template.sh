#!/usr/bin/env bash
# Crée un template Ubuntu 24.04 cloud-init avec qemu-guest-agent.
# À lancer en root sur le nœud Proxmox qui portera le template.
# Usage : bash create-template.sh <vmid> [stockage]
#   ex. : bash create-template.sh 9000            (pve01)
#         bash create-template.sh 9001 local-lvm  (pve02)
set -euo pipefail

VMID="${1:?Usage : $0 <vmid> [stockage]}"
STORAGE="${2:-local-lvm}"
NAME="ubuntu-2404-template-$(hostname)"
IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMG="/root/noble-server-cloudimg-amd64.img"

if qm status "$VMID" >/dev/null 2>&1; then
  echo "Erreur : la VM $VMID existe déjà (les numéros sont uniques dans tout le cluster)." >&2
  exit 1
fi

# 1. Image cloud + agent QEMU (sans lui, Terraform attend indéfiniment)
[ -f "$IMG" ] || wget -O "$IMG" "$IMG_URL"
command -v virt-customize >/dev/null || apt install -y libguestfs-tools
virt-customize -a "$IMG" --install qemu-guest-agent --truncate /etc/machine-id

# 2. VM de base
qm create "$VMID" --name "$NAME" --memory 2048 --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --ostype l26 \
  --agent enabled=1 --serial0 socket --vga serial0
qm set "$VMID" --scsi0 "$STORAGE:0,import-from=$IMG,discard=on,ssd=1"
qm set "$VMID" --ide2 "$STORAGE:cloudinit" --boot order=scsi0
qm disk resize "$VMID" scsi0 20G

# 3. Conversion en template
qm template "$VMID"
echo "Template $VMID ($NAME) prêt sur $(hostname), stockage $STORAGE."
