#!/usr/bin/env bash
set -euo pipefail

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for argocd-server to roll out (can take a couple of minutes on first pull)..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

echo
echo "Argo CD is up. Reach the UI with:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8443:443"
echo "  open https://localhost:8443   (username: admin)"
echo
echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
echo
echo "(That secret only exists until you change the password or delete it yourself.)"
