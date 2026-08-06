#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if grep -rl "YOUR_USERNAME/YOUR_REPO" "${REPO_ROOT}/argocd" >/dev/null 2>&1; then
  echo "ERROR: argocd/*.yaml still contains the placeholder repo URL."
  echo "Run ./scripts/00-set-repo-url.sh <your-git-url> first, commit + push, then re-run this."
  exit 1
fi

kubectl apply -f "${REPO_ROOT}/argocd/root-app.yaml"

echo
echo "Root application applied. Argo CD will now pull argocd/apps/ from git and create"
echo "the vllm and open-webui Applications from there. Track progress with:"
echo "  kubectl -n argocd get applications"
