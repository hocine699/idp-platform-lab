#!/usr/bin/env bash
# Installe Prometheus + Grafana + Alertmanager (kube-prometheus-stack).
# Identifiants Grafana fournis par Vault via ESO (secret/grafana/admin).
# Relançable sans risque.
set -euo pipefail

CHART_VERSION="91.8.1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${REPO_DIR}/platform/monitoring"

echo "==> 1/4 Identifiants Grafana depuis Vault"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${DIR}/externalsecret.yaml"
kubectl -n monitoring wait externalsecret/grafana-admin --for=condition=Ready --timeout=60s

echo "==> 2/4 Installation de kube-prometheus-stack ${CHART_VERSION}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update > /dev/null
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "${CHART_VERSION}" --namespace monitoring \
  -f "${DIR}/values.yaml" --wait --timeout 10m

echo "==> 3/4 Route grafana.devops-hme.cloud"
kubectl apply -f "${DIR}/httproute.yaml"

echo "==> 4/4 Vérification"
kubectl -n monitoring get pods
