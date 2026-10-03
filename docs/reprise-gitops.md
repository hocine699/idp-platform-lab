# Reprendre un existant sous GitOps (ArgoCD)

Méthode suivie le 3 octobre 2026 pour confier à ArgoCD des briques installées à la main.
Principe : on change la façon de gérer, pas le comportement.

## Les 7 étapes

1. **Inventaire** — ce qui tourne, en quelle version, et comment il a été installé (`helm list -A` révèle les installations Helm).
2. **Capturer la configuration réelle** — arguments, values (`helm get values`), réglages ajoutés à la main après coup.
3. **Repérer les champs immutables** — selector des Deployments, StorageClass (provisioner, reclaimPolicy, volumeBindingMode), volumeClaimTemplates des StatefulSets.
4. **Prévisualiser** — `helm template`, puis l'App Diff d'ArgoCD, en synchronisation manuelle.
5. **Basculer** — si un champ immutable bloque : supprimer l'objet, ArgoCD le recrée.
   StatefulSet : `kubectl delete sts <nom> --cascade=orphan` (pods et disques conservés).
   Ne jamais supprimer un PVC ni une StorageClass qui porte des données.
6. **Tester pour de vrai** — la fonction de la brique, pas seulement le statut `Healthy`.
7. **Passer en automatique** — `syncPolicy.automated` (prune + selfHeal), une fois tout confirmé.

## Cas 1 : metrics-server

| Point | Valeur |
|---|---|
| Installé à l'origine | manifeste par URL, v0.9.0 |
| Repris avec | chart Helm officiel 3.14.0 (appVersion 0.9.0) |
| Réglage propre | `--kubelet-insecure-tls` (certificats kubelet auto-signés) |
| Piège | selector `k8s-app` (manifeste) ≠ `app.kubernetes.io/*` (chart) |
| Bascule | suppression du Deployment, coupure d'une minute de `kubectl top` |
| Test | `kubectl top nodes`, puis `kubectl scale --replicas=0` corrigé par ArgoCD |

## Cas 2 : local-path-provisioner

| Point | Valeur |
|---|---|
| Installé à l'origine | manifeste par URL, v0.0.35 |
| Repris avec | chart lu dans le dépôt Git du projet (pas de dépôt Helm publié), tag v0.0.35 |
| Réglages forcés | `provisionerName: rancher.io/local-path`, `defaultClass: true`, chemin `/opt/local-path-provisioner` |
| Piège 1 | provisioner immutable et lié aux volumes existants |
| Piège 2 | `is-default-class` ajouté à la main, à `false` par défaut dans le chart |
| Bascule | suppression du Deployment, volumes existants non touchés |
| Reste à faire | test d'un vrai PVC, puis synchronisation automatique |
