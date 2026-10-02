# idp-platform-lab

Plateforme interne complète construite sur du matériel bare-metal récupéré : de l'hyperviseur jusqu'au portail développeur.

Ce dépôt accompagne une formation vidéo. Chaque étape y est reproductible sur une machine personnelle, sans cloud et sans abonnement.

## Ce que contient la plateforme

| Couche | Composant |
|---|---|
| Hyperviseur | Proxmox VE — cluster de 2 nœuds + arbitre QDevice sur NAS |
| Provisionnement | Terraform (provider bpg/proxmox) + templates cloud-init |
| Configuration | Ansible (kubeadm, containerd, CNI) |
| Orchestration | Kubernetes 1.35 — 1 control plane, 4 workers |
| Réseau | Cilium (CNI, Gateway API, LB-IPAM) |
| Exposition | Cloudflare Tunnel + Cloudflare Access |
| DNS interne | AdGuard Home (le trafic interne ne sort pas par Internet) |
| GitOps | ArgoCD |
| Promotion | Kargo |
| Registre | Harbor |
| Secrets | Vault + External Secrets Operator |
| Certificats | cert-manager |
| Portail développeur | Backstage (catalogue, découverte GitHub, MCP) |
| Observabilité | Prometheus, Grafana, Alertmanager, Loki, Alloy, Tempo (OpenTelemetry) |

## Matériel de référence

La plateforme tourne sur deux mini PC d'occasion et un NAS. Rien n'est spécifique à ces modèles, seuls les ordres de grandeur comptent.

- Nœud 1 : 8 cœurs / 16 threads, 32 Go de RAM, NVMe 500 Go
- Nœud 2 : Ryzen 5 3550H (4 cœurs / 8 threads), 32 Go de RAM, NVMe 512 Go
- NAS : Synology (DNS interne, PostgreSQL, arbitre de quorum)

Le chapitre d'évaluation du matériel d'occasion (lecture du SMART, choix des supports selon leur usure) fait partie de la formation.

## Structure du dépôt

```
.
├── scripts/          # template cloud-init Proxmox, installations
├── terraform/        # provisionnement des VMs
├── platform/         # manifestes de la plateforme (gateway, tunnel, monitoring, tracing…)
├── apps/             # applications déployées par ArgoCD
├── catalog/          # entités du catalogue Backstage
├── ETAT-HOMELAB.md   # état détaillé de l'installation (machines, IP, recettes)
└── docs/
    └── frictions.md  # blocages rencontrés, causes et corrections
```

Le fichier `docs/frictions.md` mérite un détour : il recense les problèmes réellement rencontrés pendant la construction, avec leur diagnostic. C'est souvent plus utile que la documentation officielle.

## Mise en route

### 1. Template de base

Sur chaque nœud Proxmox (un template local ne se clone pas vers un autre nœud) :

```bash
bash scripts/create-template.sh 9000    # 9001 sur le deuxième nœud
```

Le script télécharge l'image cloud Ubuntu, y injecte qemu-guest-agent, et la convertit en template.

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

Le playbook Ansible est maintenu dans un dépôt distinct : `deploiement-cluster-k8s-ubuntu24`

```bash
ansible all -m ping
ansible-playbook playbooks/site.yml
```

Pour ajouter des workers à un cluster existant sans toucher au control plane :

```bash
ansible-playbook playbooks/add-workers.yml --limit k8s-worker-03,k8s-worker-04
```

### 4. Vérification

```bash
kubectl get nodes
```

## Conventions

**Nommage** — `k8s-cp-01` pour le control plane, `k8s-worker-01` et suivants pour les workers. Le terme master n'est plus utilisé, conformément à l'usage Kubernetes depuis la version 1.20.

**Adressage** — le nom, l'identifiant Proxmox et l'adresse IP se déduisent les uns des autres. En situation de diagnostic, ne pas avoir à consulter un tableau fait gagner du temps.

**Secrets** — aucun secret n'est versionné. Le `.gitignore` exclut les `*.tfstate`, `*.tfvars` et les clés privées. Le state Terraform contient des informations sensibles en clair. Les secrets applicatifs vivent dans Vault et sont injectés par External Secrets.

## Avertissement

Cette plateforme est un environnement d'apprentissage. Plusieurs choix y sont volontairement simplifiés et ne conviennent pas à un usage réel : compte d'administration partagé, NetworkPolicies partielles, state Terraform local, volumes de données sur stockage local.

Chacun de ces points est traité comme un sujet à part entière dans la suite de la formation.

## Licence

MIT
