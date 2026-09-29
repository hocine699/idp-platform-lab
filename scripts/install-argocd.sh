#!/usr/bin/env bash
# Installe Argo CD derrière le Gateway (HTTPRoute), sans Ingress.
# Relançable sans risque.
set -euo pipefail

ARGOCD_VERSION="v3.5.3"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/4 Installation d'Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side : les CRDs d'Argo CD sont trop grosses pour un apply classique.
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" > /dev/null

echo "==> 2/4 Mode HTTP interne (le HTTPS est fait par Cloudflare ou le Gateway)"
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=300s

echo "==> 3/4 Route argocd.devops-hme.cloud"
kubectl apply -f "${REPO_DIR}/platform/argocd/httproute.yaml"

echo "==> 4/4 Vérification"
kubectl -n argocd get pods
echo
echo "Mot de passe admin initial : kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
