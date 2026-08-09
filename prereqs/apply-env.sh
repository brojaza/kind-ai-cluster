#!/usr/bin/env bash
# Writes values from prereqs/.env into git-tracked files - the only way to keep a
# single source of truth for these without adding runtime env-var support Argo CD
# doesn't have: it reads argocd/appsets/*.yaml and argocd/{workload,platform}-apps/*.yaml
# straight from git, continuously, with no concept of a shell env var. So "global env
# var" here means "substituted into committed files by this script before you commit",
# not an actual env var read at deploy time - same tradeoff as GIT_REPO_URL below,
# just extended to a few more knobs.
#
# Two kinds of substitution happen:
#
# 1. GIT_REPO_URL -> argocd/root-app.yaml, argocd/appsets/*.yaml (the only files that
#    carry a repoURL - argocd/workload-apps/*.yaml and argocd/platform-apps/*.yaml
#    don't; the ApplicationSets supply it). Matched by replacing the literal
#    placeholder URL text.
#
# 2. Everything else -> matched by a ` # PREREQS:<NAME>` trailing-comment anchor on
#    the target line in the relevant app's params file under argocd/workload-apps/ or
#    argocd/platform-apps/, not by matching the current value (unlike GIT_REPO_URL's
#    placeholder-text match, a value like "true" or "300" isn't unique enough within a
#    file to safely blind-replace). These params files feed each chart via a Helm
#    parameter in the matching ApplicationSet's templatePatch - not the chart's own
#    values.yaml directly (which only holds the standalone-`helm install` default) -
#    see argocd/workload-apps/vllm.yaml's comment. Search for `# PREREQS:` across
#    argocd/ to see every anchor.
#
# Safe to re-run any time .env changes - every substitution is idempotent (matches
# on the anchor/placeholder, not on "value differs from default").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} not found."
  echo "Run: cp prereqs/.env.example prereqs/.env, then edit it."
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

# The rest are optional - default to the values already committed as of this script,
# so an older .env from before these existed (or one that just doesn't set them)
# still works and is a harmless no-op.
: "${ARGOCD_HOST:=argocd.company.test}"
: "${CHAT_HOST:=chat.company.test}"
: "${VLLM_GPU_ENABLED:=true}"
: "${VLLM_SCALE_TO_ZERO_ENABLED:=true}"
: "${VLLM_SCALEDOWN_PERIOD:=300}"

PLACEHOLDER="https://github.com/YOUR_USERNAME/YOUR_REPO.git"

for f in "${REPO_ROOT}/argocd/root-app.yaml" "${REPO_ROOT}"/argocd/appsets/*.yaml; do
  sed -i.bak "s|${PLACEHOLDER}|${GIT_REPO_URL}|g" "$f"
  rm -f "${f}.bak"
  echo "Updated $f (repoURL)"
done

# set_anchored_value <file> <PREREQS marker> <new value>
# Replaces the value token on the line ending in `# PREREQS:<marker>`, leaving the
# key, indentation, and marker comment itself untouched. Warns (doesn't fail) if the
# anchor isn't found, so a chart refactor that drops one doesn't block the others.
set_anchored_value() {
  local file="$1" marker="$2" value="$3"
  if ! grep -q "# PREREQS:${marker}" "${file}"; then
    echo "WARNING: no '# PREREQS:${marker}' anchor found in ${file}, skipping" >&2
    return
  fi
  sed -i.bak "s|^\(.*: \)[^ #]*\( *# PREREQS:${marker}\)|\1${value}\2|" "${file}"
  rm -f "${file}.bak"
  echo "Updated ${file} (${marker} -> ${value})"
}

set_anchored_value "${REPO_ROOT}/argocd/platform-apps/argocd-ingress.yaml" "ARGOCD_HOST" "${ARGOCD_HOST}"
set_anchored_value "${REPO_ROOT}/argocd/workload-apps/open-webui.yaml" "CHAT_HOST" "${CHAT_HOST}"
set_anchored_value "${REPO_ROOT}/argocd/workload-apps/vllm.yaml" "VLLM_GPU_ENABLED" "\"${VLLM_GPU_ENABLED}\""
set_anchored_value "${REPO_ROOT}/argocd/workload-apps/vllm.yaml" "VLLM_SCALE_TO_ZERO_ENABLED" "\"${VLLM_SCALE_TO_ZERO_ENABLED}\""
set_anchored_value "${REPO_ROOT}/argocd/workload-apps/vllm.yaml" "VLLM_SCALEDOWN_PERIOD" "\"${VLLM_SCALEDOWN_PERIOD}\""

echo
echo "Done. Review the diff (git diff) before committing."
if [[ "${VLLM_SCALE_TO_ZERO_ENABLED}" == "true" ]]; then
  echo
  echo "REMINDER: VLLM_SCALE_TO_ZERO_ENABLED=true also requires"
  echo "charts/open-webui/values.yaml's backend.baseUrl to point at vllm-proxy (see the"
  echo "comment on that field) - this script does NOT flip that for you, and on an"
  echo "already-running cluster it also needs a manual DB patch (see the comment on"
  echo "backend.hardcodedModelId) since Open WebUI caches baseUrl after its first boot."
fi
