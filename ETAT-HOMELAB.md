# État du homelab
Dernière mise à jour : 3 octobre 2026
À coller au début de chaque nouvelle conversation avec Claude.

## Finalité
Construire une IDP (Internal Developer Platform) complète, comme en entreprise, dopée à l'IA à chaque étage.

La plateforme : un développeur crée un service depuis Backstage, et tout le reste est automatique.
- Dépôt GitHub généré depuis un modèle (golden path), inscrit dans le catalogue.
- Image construite et poussée dans Harbor.
- Déploiement par ArgoCD (GitOps), promotion par Kargo.
- Secrets fournis par Vault + External Secrets.
- Exposition via la Gateway (Cloudflare Access si privé).
- Métriques, logs et traces d'office (Prometheus, Loki, Tempo).

L'IA à chaque étage :
- Créer : on décrit un service en langage naturel, un agent choisit le golden path et le remplit (Backstage + serveur MCP, module déjà installé).
- Livrer : l'IA relit les changements et explique les plans Terraform et les écarts ArgoCD.
- Exploiter : SRE Autonome, des agents qui détectent, diagnostiquent et réparent les incidents, du matériel (Proxmox, disques, NAS) jusqu'à l'application.
- S'informer : Signal, une veille tech rédigée par l'IA et filtrée sur la stack.
Garde-fous : budgets plafonnés dans le code, citations vérifiées, et l'humain valide toute action risquée.

Signal, Radar et Backstage servent d'applications réelles pour éprouver la plateforme.

## Machines
| Machine | IP | Rôle |
|---|---|---|
| Box | 192.168.1.1 | Passerelle |
| pve01 | 192.168.1.50 | Proxmox 9.2.21 — VM 110 (k8s-cp-01), 120 (worker-01), 121 (worker-02), template 9000 |
| pve02 | 192.168.1.51 | Proxmox 9.2.21, Ryzen 5 3550H, 32 Go, NVMe 512 Go — VM 122 (worker-03), 123 (worker-04), template 9001 |
| NAS DS224 | 192.168.1.253 | AdGuard Home (DNS interne), PostgreSQL (Signal, Radar, Backstage), pgAdmin, arbitre QDevice (conteneur qnetd, port 5403, sources dans ~/qnetd), copies chiffrées des secrets Vault |
| Gateway K8s | 192.168.1.200 | Entrée interne des *.devops-hme.cloud (AdGuard réécrit vers cette IP) |
| vm-travail | — | Poste d'admin : kubectl, terraform, ansible, gpg, Claude Code |

Le NAS doit rester allumé : sans lui, plus de DNS, plus de base de données, et un vote de quorum en moins.

## Cluster Proxmox
- Nom : homelab — 2 nœuds + QDevice sur le NAS = 3 votes, quorum à 2.
- Stockage identique sur les deux nœuds : local-lvm.
- Un template local ne se clone pas vers l'autre nœud : 9000 sur pve01, 9001 sur pve02 (Ubuntu 24.04 + qemu-guest-agent).

## Kubernetes
- v1.35.9, containerd 2.2.1, Cilium 1.20.2, Ubuntu 24.04.
- Control plane 192.168.1.70 (taint NoSchedule) ; workers .71 .72 (pve01), .73 .74 (pve02).
- DNS des nœuds : AdGuard seul (192.168.1.253). Pas de 9.9.9.9, sinon le trafic vers Harbor sort par Cloudflare et casse les pulls.
- Volumes local-path tous sur worker-01/02 (Harbor, Vault, Prometheus, Loki, Tempo) : si pve01 tombe, ces applis tombent.

## Dépôts (sur vm-travail)
- ~/idp-platform-lab (main) : terraform/ (provider bpg/proxmox, VM dans vms.tf), platform/, apps/, catalog/, scripts/
- ~/deploiement-cluster-k8s-ubuntu24 (branche cilium, à fusionner dans main) : Ansible — site.yml, add-workers.yml, upgrade-cluster.yml
- ~/signal, ~/radar, ~/backstage : GitHub hocine699 (privés)

## Applications
- Signal : veille tech, signal.devops-hme.cloud, PUBLIC volontairement.
- Radar : offres DevOps chez des clients finaux, radar.devops-hme.cloud, privé (Cloudflare Access AVANT la route du tunnel). Géré par ArgoCD.
- Backstage : catalogue, découverte GitHub, module MCP installé.
- Harbor : registry.devops-hme.cloud. Tempo + Alloy : traces OpenTelemetry. Vault + External Secrets : tous les secrets.

## Monitoring de bout en bout (objectif)
Tout surveiller, de la couche matérielle jusqu'à l'application, dans un seul Grafana. C'est aussi ce qui sert d'yeux aux agents du SRE Autonome.

| Couche | Quoi surveiller | État |
|---|---|---|
| Matériel | Disques (SMART, usure NVMe), températures, alimentation des mini-PC | À faire : node-exporter + smartctl-exporter sur pve01/pve02 |
| NAS | Disques, volumes, températures, conteneurs (AdGuard, PostgreSQL, qnetd) | À faire : SNMP Synology ou exporter |
| Hyperviseur | Proxmox : nœuds, VM, stockage, quorum | Commencé : scrape de l'API Proxmox (pve-exporter) |
| Réseau | Cilium, Hubble, Gateway, DNS AdGuard | Commencé : métriques Cilium |
| Kubernetes | Nœuds, pods, ressources | En place : kube-prometheus-stack, node-exporter |
| Plateforme | ArgoCD, Kargo, Harbor, Vault (sealed ?), External Secrets, cert-manager (expiration) | À vérifier |
| Données | PostgreSQL du NAS | À faire : postgres-exporter |
| Applications | Signal, Radar, Backstage : traces, logs, métriques métier, coût IA | Commencé : traces Tempo (Signal), logs Loki |
| Vue client | Sites publics joignables (signal.devops-hme.cloud…) | À faire : sondes blackbox |
Puis : tableaux de bord par couche, et alertes Alertmanager qui alimentent les agents.

## Tout en pipeline (objectif)
Aujourd'hui, les images sont construites et poussées à la main (docker build / push). Cible : aucune action manuelle entre le commit et la production.
CI retenue : GitHub Actions avec un runner auto-hébergé dans le homelab (il joint Harbor en interne).
push sur GitHub → CI (build, tests, scan) → image dans Harbor → Kargo détecte la nouvelle version et la promeut (dev → prod) → ArgoCD synchronise le cluster.
Pareil pour l'infra : Terraform et Ansible lancés par pipeline, avec revue du plan avant application.
Chaque appli (Signal, Radar, Backstage…) doit suivre ce chemin, et le golden path Backstage doit le générer d'office.

## Composants du cluster (namespaces)
| Namespace | Rôle |
|---|---|
| argocd | Déploiements GitOps |
| kargo, kargo-* | Promotion des versions entre environnements |
| harbor | Registre d'images (registry.devops-hme.cloud) |
| backstage | Portail de l'IDP (catalogue, golden paths, MCP) |
| vault, external-secrets | Secrets : Vault les stocke, ESO les injecte dans les namespaces |
| cert-manager | Certificats TLS (wildcard, DNS-01 Cloudflare) |
| cloudflare | Tunnel Cloudflare (accès depuis Internet) |
| gateway | Gateway API (Cilium), entrée interne 192.168.1.200 |
| monitoring | Prometheus, Grafana, Alertmanager, Loki, Alloy, Tempo, node-exporter |
| local-path-storage | Volumes locaux sur les nœuds |
| agents | Agents IA du SRE Autonome |
| signal, radar, veille, demo | Applications |
| kube-system, cilium-secrets | Système (Cilium, CoreDNS…) |

## Recettes
Ajouter un worker :
1. terraform/vms.tf : ajouter une ligne (vm_id, ip, node, template), puis terraform plan → doit afficher « X to add, 0 to change, 0 to destroy », puis terraform apply.
2. Ansible : ajouter l'hôte dans inventory/inventory.yml, puis
   ansible-playbook -i inventory/inventory.yml playbooks/add-workers.yml --limit <nouveaux>

Après un redémarrage de pve01 :
- vault-unseal (raccourci dans ~/.bashrc, demande le code gpg, 3 clés sur 5)
- kubectl get pods -A | grep -vE "Running|Completed"

Vault :
- vault-on : tunnel vers Vault pour la CLI
- gpg -d ~/vault-init.json.gpg : lire le coffre (clés + token root)
- ~/vault-export.tar.gz.gpg : ancien export chiffré des secrets
- Copies des deux coffres sur le NAS (~/).

## Règles
- Aucun secret dans Git ni dans le chat. Saisie avec read -s, stockage dans Vault.
- Appli privée : Cloudflare Access d'abord, route du tunnel ensuite.
- Claude Code en mode normal, jamais en mode auto. Jamais de variable ANTHROPIC_API_KEY pour les applis.
- Commits sans mention d'IA.
- Je tape les commandes moi-même ; les déploiements passent par ArgoCD, les push à la main.

## Feuille de route
1. Tout en pipeline : CI → Harbor → Kargo → ArgoCD pour chaque appli.
2. Premier golden path Backstage : créer un service de bout en bout.
3. Agent IA qui utilise ce golden path via MCP (« crée-moi une API Python avec PostgreSQL »).
4. SRE Autonome branché sur la plateforme.

## À faire
- Extinction la nuit (0 h 30) et réveil auto (8 h 30) avec rtcwake : tester d'abord sur pve02.
- Déverrouillage automatique de Vault (job toutes les 5 min, clés dans un Secret).
- Décaler les CronJobs Signal/Radar après 8 h 30.
- Radar : vérifier la mise en ligne du site 0.2.0 et Cloudflare Access.
- Fusionner la branche cilium dans main (dépôt Ansible).
- Répartir les volumes : tout est sur pve01.
- Backstage : onglet Kubernetes. ArgoCD : gérer aussi Signal et Backstage.
- pve02 : vérifier que /etc/resolv.conf pointe sur 192.168.1.253.
