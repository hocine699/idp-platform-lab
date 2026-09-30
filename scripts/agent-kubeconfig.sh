#!/usr/bin/env bash
# Fabrique le fichier de connexion (kubeconfig) de l'agent SRE.
# Badge en LECTURE SEULE (rôle "view"), valable 24 h : relancer chaque jour.
set -euo pipefail

OUT="${HOME}/.kube/agent-readonly"

# Adresse du cluster et son certificat : copiés depuis TON kubeconfig.
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Jeton temporaire du compte sre-agent (expire tout seul dans 24 h).
TOKEN=$(kubectl -n agents create token sre-agent --duration=24h)

umask 077   # fichier lisible par toi seul
cat > "${OUT}" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: homelab
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA}
users:
  - name: sre-agent
    user:
      token: ${TOKEN}
contexts:
  - name: sre-agent@homelab
    context:
      cluster: homelab
      user: sre-agent
current-context: sre-agent@homelab
EOF

echo "Badge de l'agent écrit dans ${OUT} (valable 24 h)"
echo
echo "--- Test 1 : lire les pods (doit marcher)"
KUBECONFIG="${OUT}" kubectl get pods -n backstage
echo
echo "--- Test 2 : supprimer un pod (doit être refusé)"
KUBECONFIG="${OUT}" kubectl delete pods --all -n backstage --dry-run=server 2>&1 | head -1 || true
