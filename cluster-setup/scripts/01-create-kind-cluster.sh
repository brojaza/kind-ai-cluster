#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="kind-ai-cluster"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists, skipping creation."
  echo "(Run 'kind delete cluster --name ${CLUSTER_NAME}' first if you changed kind-config.yaml.)"
else
  kind create cluster --config "${SCRIPT_DIR}/kind-config.yaml"
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"
