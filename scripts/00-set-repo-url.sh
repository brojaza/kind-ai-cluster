#!/usr/bin/env bash
# Replaces the placeholder repoURL in every Argo CD Application manifest with the
# real git remote you're going to push this project to.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <git-repo-url>"
  echo "Example: $0 https://github.com/alice/qwen3-coder-stack.git"
  exit 1
fi

REPO_URL="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLACEHOLDER="https://github.com/YOUR_USERNAME/YOUR_REPO.git"

for f in "${REPO_ROOT}/argocd/root-app.yaml" "${REPO_ROOT}"/argocd/apps/*.yaml; do
  sed -i.bak "s|${PLACEHOLDER}|${REPO_URL}|g" "$f"
  rm -f "${f}.bak"
  echo "Updated $f"
done

echo "Done. repoURL is now ${REPO_URL} in argocd/root-app.yaml and argocd/apps/*.yaml"
