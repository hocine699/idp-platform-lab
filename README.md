# idp-platform-lab

Plateforme interne complète construite sur du matériel bare-metal récupéré :
de l'hyperviseur jusqu'au portail développeur.

Ce dépôt accompagne une formation vidéo. Chaque étape y est reproductible sur
une machine personnelle, sans cloud et sans abonnement.

---

## Ce que contient la plateforme

| Couche | Composant |
|---|---|
| Hyperviseur | Proxmox VE |
| Provisionnement | Terraform (provider `bpg/proxmox`) + templates cloud-init |
| Configuration | Ansible (kubeadm, containerd, CNI) |
| Orchestration | Kubernetes 1.35 — 1 control plane, 2 workers |
| Réseau | Flannel, ingress-nginx |
| Exposition | Cloudflare Tunnel + Cloudflare Access |
| GitOps | ArgoCD |
| Promotion | Kargo |
| Registre | Harbor |
| Certificats | cert-manager |

---

## Matériel de référence

La plateforme tourne sur un mini PC d'occasion. Rien n'est spécifique à ce
modèle, seuls les ordres de grandeur comptent.

- **CPU** : 8 cœurs / 16 threads
- **RAM** : 32 Go minimum, 64 Go confortable
- **Disque** : un NVMe de 500 Go

Le chapitre d'évaluation du matériel d'occasion (lecture du SMART, choix des
supports selon leur usure) fait partie de la formation.

---

## Structure du dépôt

```
.
├── scripts/          # création du template cloud-init Proxmox
├── terraform/        # provisionnement des VMs
├── platform/         # manifestes de la plateforme (ingress, tunnel)
├── apps/             # applications déployées par ArgoCD
└── docs/
    └── frictions.md  # blocages rencontrés, causes et corrections
```

Le fichier `docs/frictions.md` mérite un détour : il recense les problèmes
réellement rencontrés pendant la construction, avec leur diagnostic. C'est
souvent plus utile que la documentation officielle.

---

## Mise en route

### 1. Template de base

Sur le nœud Proxmox :

```bash
bash scripts/create-template.sh
```

Le script télécharge l'image cloud Ubuntu, y injecte `qemu-guest-agent`,
et la convertit en template.

### 2. Provisionnement des nœuds

Depuis le poste de travail :

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # y placer le token Proxmox
terraform init
terraform plan
terraform apply
```

### 3. Déploiement du cluster

Le playbook Ansible est maintenu dans un dépôt distinct :
[deploiement-cluster-k8s-ubuntu24](https://github.com/hocine699/deploiement-cluster-k8s-ubuntu24)

```bash
ansible all -m ping
ansible-playbook playbooks/site.yml
```

### 4. Vérification

```bash
kubectl get nodes
```

---

## Conventions

**Nommage** — `k8s-cp-01` pour le control plane, `k8s-worker-01` et suivants
pour les workers. Le terme *master* n'est plus utilisé, conformément à
l'usage Kubernetes depuis la version 1.20.

**Adressage** — le nom, l'identifiant Proxmox et l'adresse IP se déduisent
les uns des autres. En situation de diagnostic, ne pas avoir à consulter un
tableau fait gagner du temps.

**Secrets** — aucun secret n'est versionné. Le `.gitignore` exclut les
`*.tfstate`, `*.tfvars` et les clés privées. Le state Terraform contient des
informations sensibles en clair.

---

## Avertissement

Cette plateforme est un environnement d'apprentissage. Plusieurs choix y sont
volontairement simplifiés et ne conviennent pas à un usage réel : compte
d'administration partagé, absence de NetworkPolicies, state Terraform local,
certificats auto-signés en interne.

Chacun de ces points est traité comme un sujet à part entière dans la suite
de la formation.

---

## Licence

MIT# idp-platform-lab
