#!/usr/bin/env bash
# Installe Harbor derrière le Gateway. Mot de passe admin fourni par Vault via ESO.
# Prérequis : secret/harbor/admin (champ "password") existe dans Vault.
# Relançable sans risque.
set -euo pipefail

HARBOR_CHART_VERSION="1.19.2"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${REPO_DIR}/platform/harbor"

echo "==> 1/4 Mot de passe admin depuis Vault"
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${DIR}/externalsecret.yaml"
kubectl -n harbor wait externalsecret/harbor-admin --for=condition=Ready --timeout=60s

echo "==> 2/4 Installation de Harbor (chart ${HARBOR_CHART_VERSION})"
helm repo add harbor https://helm.goharbor.io --force-update > /dev/null
helm upgrade --install harbor harbor/harbor --version "${HARBOR_CHART_VERSION}" \
  --namespace harbor -f "${DIR}/values.yaml" --wait --timeout 10m

echo "==> 3/4 Route registry.devops-hme.cloud"
kubectl apply -f "${DIR}/httproute.yaml"

echo "==> 4/4 Vérification"
kubectl -n harbor get pods
