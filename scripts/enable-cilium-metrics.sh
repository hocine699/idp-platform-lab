#!/usr/bin/env bash
# Active les métriques Cilium/Hubble/Envoy et leurs tableaux de bord Grafana.
# Garde tous les réglages posés par Ansible (--reuse-values) et y ajoute
# platform/cilium/metrics-values.yaml.
# Prérequis : install-monitoring.sh (CRDs ServiceMonitor).
set -euo pipefail

CILIUM_VERSION="1.20.2"   # doit rester égal à cilium_version dans Ansible
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

helm repo add cilium https://helm.cilium.io/ --force-update > /dev/null

echo "==> 1/2 Mise à jour de Cilium ${CILIUM_VERSION} (métriques)"
helm upgrade cilium cilium/cilium --version "${CILIUM_VERSION}" \
  --namespace kube-system --reuse-values \
  -f "${REPO_DIR}/platform/cilium/metrics-values.yaml"

echo "==> 2/2 Redémarrage progressif des agents Cilium"
kubectl -n kube-system rollout status daemonset/cilium --timeout=5m
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl get servicemonitor -A | grep -iE "cilium|hubble|envoy"
