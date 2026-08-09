#!/usr/bin/env bash
# Replaces the placeholder repoURL in every Argo CD manifest that carries one
# (argocd/root-app.yaml, argocd/appsets/*.yaml) with GIT_REPO_URL from prereqs/.env.
#
# Only those files need it: argocd/workload-apps/*.yaml and argocd/platform-apps/*.yaml
# (the per-app params) don't carry a repoURL themselves - the two ApplicationSets
# supply it for every Application they generate from those files.
#
# Note this only changes *how* the URL gets written into git-tracked files (from a
# .env file instead of a CLI arg) - it still ends up committed, same as before. Argo
# CD reads argocd/appsets/*.yaml continuously from git itself; it has no concept of
# shell env vars, so there's no way to keep the real URL out of git entirely without
# wrapping argocd/appsets in a Helm chart and passing repoURL down as a parameter -
# not worth the complexity for a single-fork project like this one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} not found."
  echo "Run: cp prereqs/.env.example prereqs/.env, then edit GIT_REPO_URL in it."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

if [[ -z "${GIT_REPO_URL:-}" ]]; then
  echo "ERROR: GIT_REPO_URL is not set in ${ENV_FILE}"
  exit 1
fi

PLACEHOLDER="https://github.com/YOUR_USERNAME/YOUR_REPO.git"

for f in "${REPO_ROOT}/argocd/root-app.yaml" "${REPO_ROOT}"/argocd/appsets/*.yaml; do
  sed -i.bak "s|${PLACEHOLDER}|${GIT_REPO_URL}|g" "$f"
  rm -f "${f}.bak"
  echo "Updated $f"
done

echo "Done. repoURL is now ${GIT_REPO_URL} in argocd/root-app.yaml and argocd/appsets/*.yaml"
