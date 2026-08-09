#!/usr/bin/env bash
# Installs KEDA core + the KEDA HTTP Add-on, cluster infra needed for scaling vLLM to
# zero replicas when idle (freeing the GPU) and transparently waking it back up on the
# next request. Out-of-band, same as ingress-nginx (05-install-ingress.sh) -
# not git/Argo CD-managed.
#
# After this script, enable it per-app via values.yaml (see charts/vllm/values.yaml's
# autoscaling.scaleToZero block and the matching note in charts/open-webui/values.yaml).
set -euo pipefail

helm repo add kedacore https://kedacore.github.io/charts >/dev/null
helm repo update kedacore >/dev/null

echo "Installing KEDA core..."
helm upgrade --install keda kedacore/keda --namespace keda --create-namespace --wait

echo "Installing KEDA HTTP Add-on..."
helm upgrade --install http-add-on kedacore/keda-add-ons-http --namespace keda --wait

echo
echo "KEDA + HTTP Add-on installed. Now set charts/vllm/values.yaml's"
echo "autoscaling.scaleToZero.enabled to true, point charts/open-webui/values.yaml's"
echo "backend.baseUrl at the vllm-proxy Service it creates, and let Argo CD sync (or"
echo "'helm upgrade' directly if you're not using Argo CD)."
