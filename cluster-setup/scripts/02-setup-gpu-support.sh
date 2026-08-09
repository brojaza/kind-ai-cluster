#!/usr/bin/env bash
set -euo pipefail

# Installs the NVIDIA device plugin DaemonSet so the cluster can schedule pods that
# request nvidia.com/gpu. This is only the IN-CLUSTER half of GPU setup. Before running
# this, make sure (see README.md "GPU passthrough for Kind"):
#   1. The Kind host has an NVIDIA GPU with a recent driver installed.
#   2. NVIDIA Container Toolkit is installed on the host.
#   3. Docker's default runtime is set to "nvidia" on the host.
#   4. kind-config.yaml's containerdConfigPatches block was uncommented BEFORE the
#      cluster was created (recreate the cluster if you just uncommented it now).

echo "Installing NVIDIA device plugin..."
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/main/deployments/static/nvidia-device-plugin.yml

echo "Waiting for the device plugin DaemonSet to roll out..."
kubectl -n kube-system rollout status daemonset/nvidia-device-plugin-daemonset --timeout=120s

echo
echo "Allocatable GPUs per node (should show a number, not <none>):"
kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.'nvidia\.com/gpu'
