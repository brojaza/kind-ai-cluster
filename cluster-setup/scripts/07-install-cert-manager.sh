#!/usr/bin/env bash
# Installs cert-manager - out-of-band cluster infra, same as ingress-nginx
# (05) and KEDA (06), not git/Argo CD-managed. Lets Ingress objects
# request TLS certs declaratively via annotations instead of a manual openssl +
# kubectl create secret step.
#
# Locally this backs a SelfSigned ClusterIssuer (charts/cert-manager/templates/selfsigned-clusterissuer.yaml,
# git/Argo CD-managed - requires this script to have run first, same CRD-ordering
# caveat as KEDA's HTTPScaledObject). Moving to a real cluster later means swapping
# that ClusterIssuer for an ACME/Let's Encrypt or internal-CA one - nothing else
# (the Ingress objects, the annotations referencing it) needs to change.
set -euo pipefail

helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo update jetstack >/dev/null

echo "Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --wait

echo
echo "cert-manager installed. Argo CD will pick up charts/cert-manager's selfsigned-clusterissuer.yaml"
echo "(and issue a cert for any Ingress referencing it) on its next sync - force one with:"
echo "  kubectl -n argocd annotate application cert-manager-issuer argocd.argoproj.io/refresh=hard --overwrite"
