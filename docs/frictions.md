# Frictions rencontrées lors de la construction

Journal des blocages réels rencontrés pendant la construction de la plateforme.
Chaque entrée = symptôme, cause, correction, et l'angle pédagogique à exploiter en vidéo.

---

## 1. Agent QEMU absent de l'image cloud

**Symptôme**
`terraform apply` reste bloqué sur `Still creating...` pendant plus de 10 minutes.
La VM apparaît pourtant bien dans Proxmox et démarre normalement.

**Cause**
Le provider `bpg/proxmox` attend que l'agent QEMU réponde pour récupérer l'adresse IP
de la VM. L'image cloud Ubuntu officielle n'embarque pas `qemu-guest-agent`.
Le paramètre `agent { enabled = true }` active l'attente côté hyperviseur,
mais rien ne répond côté invité.

**Correction**
Injecter l'agent dans l'image **avant** de créer le template :

```bash
apt install libguestfs-tools -y
virt-customize -a noble-server-cloudimg-amd64.img --install qemu-guest-agent
```

**Angle pédagogique**
Excellente introduction à la différence entre « la VM tourne » et « l'orchestrateur
sait que la VM tourne ». Montrer le blocage en direct, puis le résoudre.
Introduit aussi `virt-customize`, outil peu connu et très utile.

---

## 2. Token API Proxmox — trois pièges enchaînés

**Symptôme**
```
HTTP 403 - Reason: Permission check failed (/vms/9000, VM.Clone)
```

**Causes** (trois distinctes, à traiter séparément)

1. **Realm confondu** — créer un utilisateur nommé `terraform@pve` dans le realm PAM
   produit l'identifiant `terraform@pve@pam`, qui n'est pas `terraform@pve`.
   Le realm fait partie de l'identité, il ne se tape pas dans le nom.

2. **Privilege separation** — activée par défaut, elle empêche le token d'hériter
   des droits de son utilisateur. Le token a alors zéro permission.

3. **Propagation** — une ACL posée sur `/` sans `propagate` ne descend pas
   sur `/vms/9000`.

**Correction**
```bash
pveum user add terraform@pve
pveum acl modify / --user terraform@pve --role PVEAdmin
pveum user token add terraform@pve tf --privsep 0
```

**Angle pédagogique**
Module entier sur le modèle de permissions Proxmox. Montrer les trois erreurs
une par une plutôt que de donner la config finale. Enchaîner sur le principe
du moindre privilège : `PVEAdmin` est pratique en lab, mais en production
on découpe les rôles.

---

## 3. group_vars invisible selon l'emplacement du playbook

**Symptôme**
```
'common_packages' is undefined
```
alors que la variable est bien définie dans `group_vars/all.yml`.

**Cause**
Ansible cherche `group_vars/` **relativement au playbook**. Des playbooks rangés
dans `playbooks/` font chercher `playbooks/group_vars/`, qui n'existe pas.
Le dossier à la racine du projet est ignoré.

**Correction**
Déplacer `group_vars/` à côté du fichier d'inventaire :

```bash
mv group_vars inventory/group_vars
```

Ansible le charge alors systématiquement, quel que soit le répertoire d'exécution.

**Angle pédagogique**
La résolution des variables Ansible est une des sources de confusion les plus
fréquentes. Bon moment pour présenter la précédence complète des variables
(22 niveaux) et expliquer pourquoi ranger ses playdbooks dans un sous-dossier
casse les conventions implicites.

---

## 4. State Terraform local et divergence avec la réalité

**Symptôme**
`terraform destroy` répond qu'il n'y a rien à détruire, alors que la VM existe
bien dans Proxmox. Ou l'inverse : `apply` échoue car l'ID de VM est déjà pris.

**Cause**
Le state est un fichier local (`terraform.tfstate`) présent uniquement dans le
répertoire où `apply` a été lancé. Lancer les commandes depuis un autre dossier
donne un state vide. Un `Ctrl+C` en cours de création peut aussi laisser le state
désynchronisé de la réalité.

**Correction immédiate**
```bash
cd <le bon dossier>
terraform state list
```
Et si nécessaire, nettoyer manuellement :
```bash
qm stop <vmid> && qm destroy <vmid>
terraform state rm <resource>
```

**Angle pédagogique**
C'est **l'** argument qui justifie un backend distant. Montrer la casse avec un
state local, puis introduire le backend S3 (MinIO auto-hébergé ou NAS).
Enchaîner sur le verrouillage d'état en travail à plusieurs, et sur le fait que
le state contient des secrets en clair — d'où le `.gitignore`.

---

## 5. Renommage `masters` → `control_plane`

**Symptôme**
Renommer un groupe dans l'inventaire casse 22 références réparties dans les rôles,
les playbooks et les group_vars.

**Cause**
Un nom de groupe Ansible n'est pas qu'une étiquette : il est référencé par
`hosts:` et par `groups['nom']` un peu partout. Renommer l'inventaire seul
produit des `undefined` silencieux ou des plays qui ne ciblent rien.

**Correction**
```bash
git checkout -b rename-control-plane
grep -rl "masters" roles/ playbooks/ group_vars/ | xargs sed -i \
  "s/groups\['masters'\]/groups['control_plane']/g; s/hosts: masters/hosts: control_plane/g"
grep -rn "masters" roles/ playbooks/ group_vars/   # vérification
```

**Angle pédagogique**
Double intérêt. D'abord le fond : Kubernetes a abandonné « master » depuis la 1.20,
utiliser le vocabulaire à jour compte. Ensuite la méthode : faire ce type de
refactoring dans une branche, vérifier par grep, tester avant de fusionner.
C'est du Git appliqué à de l'infrastructure.

---

## 6. Dimensionnement mémoire — l'affichage trompeur

**Symptôme**
Proxmox affiche 26 % de RAM utilisée avec 4 VMs démarrées totalisant 20 Go alloués.
On croit avoir de la marge.

**Cause**
L'affichage reflète la mémoire **réellement touchée**, pas l'allocation.
Des VMs fraîchement démarrées n'ont encore rien écrit. Dès que les workloads
montent en charge, la consommation rejoint l'allocation.

**Points connexes**
- KSM affiche 0 B tant que l'occupation reste faible : le démon n'active la
  déduplication qu'au-delà d'un seuil (~80 %).
- Sur ZFS, l'ARC prend la moitié de la RAM par défaut. Sur 32 Go, cela fait
  16 Go consommés avant même la première VM. Fixer `zfs_arc_max`.

**Angle pédagogique**
Module sur le sizing et le surengagement mémoire. Montrer le chiffre à vide,
puis après déploiement de la plateforme complète. Expliquer pourquoi
l'over-commit est utile mais dangereux, et ce qui se passe quand l'OOM killer
intervient sur un nœud Kubernetes.

---

## 7. Divers — à développer

- **Conflit de paquets `ksmtuned` / `ksm-control-daemon`** : Proxmox embarque déjà
  le second. Occasion de parler de la lecture des dépendances avant un `apt install -y`
  (l'installation voulait tirer des bibliothèques Mesa sur un hyperviseur headless).
- **FQDN obligatoire** à l'installation Proxmox : un hostname sans point fait
  échouer l'installation.
- **`.local` vs `.internal`** : `.local` est réservé à mDNS/Bonjour, source de
  conflits de résolution.
- **Authentification GitHub** : le mot de passe n'est plus accepté. Token ou SSH.
  Occasion de parler du stockage des credentials (`credential.helper store`
  écrit en clair — acceptable en lab, jamais en entreprise).
- **Une clé SSH par machine** plutôt qu'une clé copiée partout. Prépare
  l'introduction de Vault et des certificats SSH éphémères.
