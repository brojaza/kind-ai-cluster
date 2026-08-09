#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if grep -rl "YOUR_USERNAME/YOUR_REPO" "${REPO_ROOT}/argocd" >/dev/null 2>&1; then
  echo "ERROR: argocd/*.yaml still contains the placeholder repo URL."
  echo "Run: cp env-setup/.env.example env-setup/.env, set GIT_REPO_URL, then"
  echo "./env-setup/set-repo-url.sh, commit + push, then re-run this."
  exit 1
fi

kubectl apply -f "${REPO_ROOT}/argocd/root-app.yaml"

echo
echo "Root application applied. Argo CD will now pull argocd/appsets/ from git, which"
echo "in turn discovers and creates the vllm/open-webui/platform Applications from"
echo "argocd/workload-apps/ and argocd/platform-apps/. Track progress with:"
echo "  kubectl -n argocd get applications"
