#!/usr/bin/env bash
# Installe Kargo. Secrets admin lus dans Vault (secret/kargo/admin).
# Prérequis : cert-manager installé, Vault déverrouillé.
set -euo pipefail

KARGO_VERSION="1.11.4"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
vault_get() { kubectl -n vault exec vault-0 -- vault kv get -field="$1" secret/kargo/admin; }

echo "==> 1/2 Installation de Kargo ${KARGO_VERSION}"
helm upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version "${KARGO_VERSION}" --namespace kargo --create-namespace \
  -f "${REPO_DIR}/platform/kargo/values.yaml" \
  --set-string api.adminAccount.passwordHash="$(vault_get passwordHash)" \
  --set-string api.adminAccount.tokenSigningKey="$(vault_get tokenSigningKey)" \
  --wait --timeout 10m

kubectl apply -f "${REPO_DIR}/platform/kargo/httproute.yaml"

echo "==> 2/2 Vérification"
kubectl -n kargo get pods
kubectl -n kargo get svc kargo-api
