#!/usr/bin/env bash
# Installe Loki (stockage des logs) + Alloy (collecte) et branche Loki dans Grafana.
# Prérequis : install-monitoring.sh (namespace monitoring, Grafana).
# Relançable sans risque.
set -euo pipefail

LOKI_CHART_VERSION="18.13.7"
ALLOY_CHART_VERSION="1.13.0"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${REPO_DIR}/platform/logging"

helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update > /dev/null
helm repo add grafana https://grafana.github.io/helm-charts --force-update > /dev/null

echo "==> 1/4 Loki ${LOKI_CHART_VERSION}"
helm upgrade --install loki grafana-community/loki --version "${LOKI_CHART_VERSION}" \
  --namespace monitoring -f "${DIR}/loki-values.yaml" --wait --timeout 10m

echo "==> 2/4 Alloy ${ALLOY_CHART_VERSION}"
helm upgrade --install alloy grafana/alloy --version "${ALLOY_CHART_VERSION}" \
  --namespace monitoring -f "${DIR}/alloy-values.yaml" --wait --timeout 5m

echo "==> 3/4 Source de données Loki dans Grafana"
kubectl apply -f "${DIR}/grafana-datasource.yaml"

echo "==> 4/4 Vérification"
kubectl -n monitoring get pods -l 'app.kubernetes.io/name in (loki,alloy)'
kubectl -n monitoring get svc loki
