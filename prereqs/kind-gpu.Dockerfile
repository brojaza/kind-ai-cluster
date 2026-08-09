# Windows/WSL2 + Docker Desktop only - see docs/WINDOWS-SETUP.md "GPU passthrough" for
# why this exists. Docker's "nvidia" default runtime only injects the GPU into a
# container whose env already requests it; kind's stock node image doesn't set that, and
# kind-config.yaml has no field to inject env vars into the node container directly.
#
# Build:
#   docker build -t kindest/node:v1.30.0-gpu -f kind-gpu.Dockerfile .
# Then point kind-config.yaml's node `image:` at kindest/node:v1.30.0-gpu and
# (re)create the cluster - the node image can't be swapped on a running cluster.
#
# Bump the base tag here if you change kind-config.yaml / the kind version in use.
FROM kindest/node:v1.30.0
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all
