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

---

## 8. Template Proxmox local : impossible de cloner vers un autre nœud

**Symptôme**
Ajout d'un deuxième nœud (pve02). Le template 9000 n'existe que sur pve01 :
Terraform ne peut pas créer les nouvelles VM sur pve02 à partir de lui.

**Cause**
Le disque du template est sur `local-lvm`, un stockage propre à pve01.
Proxmox ne clone vers un autre nœud que si le disque est sur un stockage partagé.

**Correction**
Un template par nœud : 9000 sur pve01, 9001 sur pve02 (même image, même agent QEMU).
Dans `vms.tf`, chaque VM porte son nœud et son template :

```hcl
"k8s-worker-03" = { vm_id = 122, ip = "192.168.1.73", cores = 4, memory = 8192, node = "pve02", template = 9001 }
```

**Angle pédagogique**
Montre concrètement la différence entre stockage local et stockage partagé.
Bonne transition vers Ceph ou NFS dans un chapitre ultérieur.

---

## 9. DNS de secours public : le trafic interne part sur Internet

**Symptôme**
Un pod reste en `ImagePullBackOff`, uniquement sur un nouveau worker :
```
failed size validation: 46790 != 46644: failed precondition
```

**Cause**
Les VM avaient deux DNS : AdGuard (192.168.1.253) et 9.9.9.9 en secours.
Le NAS était éteint au moment de leur création : systemd-resolved a basculé sur 9.9.9.9
et y est resté. Quad9 ne connaît pas la réécriture interne d'AdGuard : il renvoie l'IP
publique Cloudflare, le pull passe par le tunnel, et la réponse arrive modifiée.

Diagnostic en comparant un nœud sain et le nœud malade :
```bash
getent hosts registry.devops-hme.cloud
resolvectl status | grep 'Current DNS'
```

**Correction**
AdGuard seul : retirer 9.9.9.9 du netplan (`netplan apply`), et dans `vms.tf`
garder `servers = ["192.168.1.253"]`.

**Angle pédagogique**
DNS « split-horizon » : un même nom, deux réponses selon le serveur interrogé.
Méthode de diagnostic à montrer en vidéo : comparer un nœud sain et un nœud malade.

---

## 10. Ajouter des VM fait apparaître des modifications sur les VM existantes

**Symptôme**
```
Plan: 2 to add, 3 to change, 0 to destroy.
```
Les 3 « change » portent sur `initialization.user_account.keys` des VM existantes.

**Cause**
La clé SSH lue aujourd'hui (`~/.ssh/id_ed25519.pub`) n'est pas écrite exactement
comme celle enregistrée à la création des VM.

**Correction**
Ignorer ce champ après la création :

```hcl
lifecycle {
  ignore_changes = [initialization[0].user_account, initialization[0].dns]
}
```

Règle : relire le plan, ne jamais appliquer un « change » qu'on ne comprend pas.

**Angle pédagogique**
Lire un plan Terraform avant d'appliquer. Isoler les lignes modifiées :
`terraform plan -no-color | grep -E '^\s*# |^\s*~ |^\s*- '`

---

## 11. Copier un fichier vers un NAS Synology : scp échoue

**Symptôme**
```
subsystem request failed on channel 0
scp: Connection closed
```

**Cause**
Depuis OpenSSH 9, `scp` utilise SFTP par défaut. Le service SFTP est désactivé sur DSM.

**Correction**
```bash
scp -O fichier hocine@192.168.1.253:~/
# ou, sans scp :
cat fichier | ssh hocine@192.168.1.253 "cat > ~/fichier"
```

**Angle pédagogique**
Petit piège qui fait perdre du temps : savoir qu'un outil familier a changé de protocole.

---

## 12. gpg dans un pipe : impossible de saisir la phrase de passe

**Symptôme**
```
gpg: problem with the agent: Inappropriate ioctl for device
gpg: error creating passphrase: Operation cancelled
```

**Cause**
`tar ... | gpg -c` : gpg a besoin du terminal pour demander la phrase de passe,
et le pipe occupe son entrée.

**Correction**
Passer par un fichier intermédiaire, puis l'effacer :
```bash
tar czf archive.tar.gz dossier
gpg -c archive.tar.gz
shred -u archive.tar.gz
```
(Autre option : `export GPG_TTY=$(tty)` avant la commande.)

**Angle pédagogique**
Chapitre « secrets » : chiffrer `vault-init.json` et les exports au lieu de les laisser en clair.

---

## 13. Cluster Proxmox à 2 nœuds : arbitre QDevice sur un NAS Synology

**Symptôme**
Avec 2 nœuds, si l'un s'éteint, l'autre perd le quorum : plus possible de démarrer
une VM ni de modifier la configuration. Et DSM ne permet pas d'installer `corosync-qnetd`.

**Cause**
Corosync exige la majorité des votes : 1 sur 2 ne suffit pas.

**Correction**
Un conteneur Debian sur le NAS avec `corosync-qnetd`, et un SSH temporaire
sur le port 2222 (nécessaire une seule fois pour l'échange de certificats) :
1. `docker run ... -p 5403:5403 -p 2222:22 -v qnetd-etc:/etc/corosync ...`
2. Sur pve01, `~/.ssh/config` : `Host 192.168.1.253` → `Port 2222`
3. `apt install corosync-qdevice` sur les deux nœuds, puis `pvecm qdevice setup 192.168.1.253`
4. Recréer le conteneur sans le port 2222 (les certificats restent dans le volume).

Résultat : `Total votes: 3`, `Flags: Quorate Qdevice`.

**Angle pédagogique**
Expliquer le quorum avec des votes. Montrer un nœud qui tombe sans bloquer l'autre.
