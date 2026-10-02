#!/usr/bin/env bash
# Déploie (ou met à jour) l'appli Veille. À relancer après chaque
# modification de glance.yml.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f k8s.yaml
kubectl -n veille create configmap glance-config --from-file=glance.yml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n veille rollout restart deployment/glance
kubectl -n veille rollout status deployment/glance --timeout=120s
