#!/usr/bin/env bash
# Installs the ingress-nginx controller (out-of-band, not git/Argo CD-managed) and
# configures it for the Argo CD UI/API at https://localhost:8443, replacing the
# `kubectl port-forward` workflow. The actual Ingress resource
# (manifests/argocd-ingress.yaml) is applied separately by Argo CD itself, via
# argocd/apps/argocd-ingress-app.yaml - see that file and
# docs/WINDOWS-SETUP.md for the full explanation of the port reuse.
#
# Requires scripts/03-install-argocd.sh and scripts/04-bootstrap-apps.sh to have been
# run first (the latter is what actually creates the Ingress, via Argo CD).
set -euo pipefail

INGRESS_NGINX_VERSION="controller-v1.15.1"

kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml"

echo "Waiting for the ingress-nginx controller to roll out..."
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

echo "Patching ingress-nginx-controller Service to NodePort, https on 30443 (matches"
echo "kind-config.yaml's hostPort:8443 -> containerPort:30443 mapping)..."
HTTP_NODEPORT=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
kubectl -n ingress-nginx patch svc ingress-nginx-controller -p "{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"targetPort\":\"http\",\"nodePort\":${HTTP_NODEPORT}},{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\",\"targetPort\":\"https\",\"nodePort\":30443}]}}"

echo "Enabling --enable-ssl-passthrough on the controller (required for Argo CD's"
echo "combined UI/gRPC port - not a default flag)..."
if ! kubectl -n ingress-nginx get deployment ingress-nginx-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- --enable-ssl-passthrough; then
  kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-ssl-passthrough"}]'
  kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=120s
else
  echo "  (already enabled)"
fi

echo
echo "Controller ready. The Ingress resource itself is managed by Argo CD -"
echo "make sure argocd/apps/argocd-ingress-app.yaml has synced:"
echo "  kubectl -n argocd get application argocd-ingress"
echo
echo "Once synced, Argo CD is reachable at https://localhost:8443 (self-signed cert,"
echo "your browser will warn you) - no port-forward needed. Verify with:"
echo "  curl -k https://localhost:8443/api/version"
