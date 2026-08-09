# Running this stack on Windows (Docker Desktop + WSL2 + Kind)

This documents how this project was actually gotten running on a Windows 11 machine
(Intel i5-14600K, 32GB RAM, RTX 3060 12GB) using Docker Desktop, kind, kubectl, and Helm
installed via `choco` - deployed directly with Helm, **not** Argo CD. The root `README.md`
is written for native Linux with a 48GB+ GPU; several things needed to change for this
environment. Keep this doc next to it as the Windows-specific delta.

## Summary of what's different from the root README

1. **Model swapped**: `Qwen/Qwen3-Coder-30B-A3B-Instruct` (~61GB bf16) doesn't fit a 12GB
   card at any quantization. `charts/vllm/values.yaml` now serves
   `Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` instead (~5GB VRAM for weights).
2. **GPU passthrough into Kind works completely differently on Windows.** The README's
   `nvidia-container-toolkit` + containerd-patch approach assumes real Linux
   `/dev/nvidia*` devices, which don't exist under WSL2. See "GPU passthrough" below for
   what actually works.
3. **Deployed directly via `helm install`**, skipping Argo CD entirely, per this
   environment's setup goal.
4. Two real vLLM bugs unrelated to Windows had to be worked around (see "vLLM bugs hit"
   below) - worth knowing about even on native Linux.

## Prerequisites actually used

- Docker Desktop (WSL2 backend) - confirm with `docker info` that a Windows NVIDIA driver
  with WSL2 CUDA support is installed (`docker run --rm --gpus all
  nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi` should show your GPU).
- `kind`, `kubectl`, `helm` on the Windows PATH (kubectl and helm came from
  `choco install kubernetes-cli kubernetes-helm`; `kind` was installed manually - the
  `choco install kind` package pulls in a `docker-desktop` dependency that fails without
  an elevated shell, so it's easier to grab `kind.exe` directly from
  https://kind.sigs.k8s.io/dl/ and drop it somewhere already on PATH, e.g.
  `%APPDATA%\npm`).

## Step 1: Give Docker Desktop's WSL2 VM more headroom

By default Docker Desktop's WSL2 VM gets ~50% of host RAM. On a 32GB host that's ~15.5GB,
which is tight once you add Kind's control-plane + vLLM + Open WebUI. Bumped it to 20GB:

`%USERPROFILE%\.wslconfig`:
```ini
[wsl2]
memory=20GB
```
Then `wsl --shutdown` and restart Docker Desktop. Verify: `wsl -d docker-desktop free -h`.

This is also why `charts/vllm/values.yaml`'s `resources.requests/limits` were lowered
from the README's defaults (`24Gi`/`48Gi`, sized for the 61GB model) down to `6Gi`/`10Gi` -
the old values would never schedule (`Pending` forever, requesting more memory than the
node has).

## Step 2: Docker Desktop default runtime -> nvidia

Settings -> Docker Engine -> add `"default-runtime": "nvidia"` to the JSON -> Apply &
Restart. `docker info` should then show `Default Runtime: nvidia` (the `nvidia` runtime
itself was already listed as available, just not default).

**This turned out to be necessary but not sufficient** - see the next section.

## Step 3: GPU passthrough into Kind (the actual hard part)

The root README's approach (`nvidia-container-toolkit` on the host, containerd patch
inside the kind node pointing at `/usr/bin/nvidia-container-runtime`) **does not work
under Docker Desktop on Windows**, for two independent reasons discovered by inspecting
the running node container directly:

1. Docker's `nvidia` runtime only injects the GPU into a container whose environment
   already has `NVIDIA_VISIBLE_DEVICES=all` set. Kind's stock node image doesn't set
   this, and `cluster-setup/scripts/kind-config.yaml` has no field to inject env vars
   into the node container.
2. Even after fixing that, Docker Desktop's WSL2 GPU support turned out to be its own
   internal mechanism - not the classic Linux `nvidia-container-toolkit` +
   `nvidia-container-runtime` + `/dev/nvidia*` device model at all. Windows/WSL2 exposes
   the GPU via a single paravirtualized device, `/dev/dxg`, plus userspace driver
   libraries mounted from the host at `/usr/lib/wsl/drivers/<hash>/` (the hash is
   driver-specific and not predictable ahead of time). There is no
   `/usr/bin/nvidia-container-runtime` binary anywhere in the picture, so the
   README's containerd-patch approach has nothing to invoke.

### What actually works

**3a. Custom kind node image** with the env vars baked in, so Docker's `nvidia` runtime
has something to trigger on when kind creates the node container:

See `prereqs/kind-gpu.Dockerfile`:
```dockerfile
FROM kindest/node:v1.30.0
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all
```

```
docker build -t kindest/node:v1.30.0-gpu -f prereqs/kind-gpu.Dockerfile .
```

(If you're using the Terraform path instead of the scripts, skip this - `cluster-setup/terraform/gpu-image.tf` builds this image automatically as part of `terraform apply`.)

`cluster-setup/scripts/kind-config.yaml` then pins the control-plane node to this image:
```yaml
nodes:
  - role: control-plane
    image: kindest/node:v1.30.0-gpu
```

This gets `/dev/dxg` and the WSL driver library directory mounted into the **node**
container (verify with `docker exec <node> nvidia-smi`). It does **not** automatically
propagate into individual **pod** containers the node schedules - nested containerd has
no runtime that knows to do that injection (see point 2 above).

**3b. Wire the GPU into the vLLM pod directly**, bypassing the whole
device-plugin/RuntimeClass mechanism, since there's no functioning
`nvidia-container-runtime` to route through:

- `hostPath` volume mount `/usr/lib/wsl` (read-only) and `/dev/dxg` (type `CharDevice`)
  into the container.
- `securityContext.privileged: true` - Kubernetes has no non-privileged way to grant a
  raw hostPath device node the necessary cgroup device access (Docker's `--device` flag
  does this automatically; Kubernetes' `hostPath` volumes don't).
- At container start, discover the actual driver directory (its hash suffix isn't fixed)
  and set `LD_LIBRARY_PATH` before exec'ing `vllm serve`:
  ```sh
  NVDIR=$(dirname "$(find /usr/lib/wsl/drivers -maxdepth 2 -iname nvidia-smi | head -1)")
  export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${NVDIR}:${LD_LIBRARY_PATH}"
  exec vllm serve "$@"
  ```

All of this is implemented in `charts/vllm/templates/deployment.yaml`, gated behind a new
`gpu.wsl2: true` values flag (see `charts/vllm/values.yaml`). It intentionally does
**not** request the `nvidia.com/gpu` extended resource - there's no device plugin
reporting that resource in this setup, so requesting it would leave the pod `Pending`
forever. Set `gpu.wsl2: false` if you ever run this chart on native Linux with a real
NVIDIA device plugin installed (the README's original path); `gpu.count` is what matters
there instead.

This was verified incrementally before touching the Helm chart: first a plain
`docker run --runtime=runc -v /usr/lib/wsl:/usr/lib/wsl:ro --device=/dev/dxg`, then a
minimal test Pod with the same mounts, both confirmed `nvidia-smi` works with no
`nvidia-container-runtime` involved at all.

### Caveat

The `/usr/lib/wsl/drivers/<hash>/` path is tied to the currently-installed Windows NVIDIA
driver package. A Windows driver update could change that hash - the pod's startup
script re-discovers it via `find` on every container start, so this self-heals on pod
restart without any chart changes needed.

## vLLM bugs hit (not Windows-specific)

Two real vLLM/Kubernetes issues surfaced once the GPU passthrough itself was working -
worth knowing about regardless of platform:

1. **`enableServiceLinks` collision.** Kubernetes auto-injects `<SERVICE>_SERVICE_HOST`/
   `_PORT`-style env vars into every pod for every Service in the namespace (legacy
   Docker-links behavior). Since the chart's own Service is named `vllm`, Kubernetes
   injected `VLLM_PORT=tcp://10.96.x.x:8000` - colliding with vLLM's own internal
   `VLLM_PORT` env var (used for engine-internal comms), which then fails to parse the
   URI as an int and crashes on startup. Fixed by setting `enableServiceLinks: false` on
   the pod spec. See https://docs.vllm.ai/en/latest/configuration/env_vars.html.

2. **`RuntimeError: UVA is not available`.** vLLM's newer async-scheduling GPU code path
   needs CUDA Unified Virtual Addressing (pinned host memory). vLLM deliberately disables
   pinned memory **by default whenever it detects WSL2** (`vllm/platforms/cuda.py`,
   `is_pin_memory_available()`), regardless of whether the WSL2 kernel actually supports
   it, and requires an explicit opt-in: the `VLLM_WSL2_ENABLE_PIN_MEMORY=1` env var. It
   also gates on WSL2 kernel >= 4.19.121 - check yours with `wsl -d docker-desktop uname
   -r` (Windows 11's default WSL2 kernel is far above this floor). This env var is now
   set automatically by the chart whenever `gpu.wsl2: true`.

## Deploying (Helm only, no Argo CD)

```bash
kind create cluster --config cluster-setup/scripts/kind-config.yaml
helm install vllm charts/vllm -n llm --create-namespace
kubectl -n llm logs -f deploy/vllm        # wait for "Application startup complete"
helm install open-webui charts/open-webui -n llm
```

Then open http://localhost:8080, register the first account (becomes admin), and the
model appears as `Qwen2.5-Coder-7B-Instruct-AWQ`.

Verify without a browser:
```bash
kubectl -n llm exec deploy/open-webui -- curl -sS http://vllm:8000/v1/models
```

## Troubleshooting additions for this setup

- **`docker exec <node> nvidia-smi` fails / no `/dev/dxg` in the node**: the node was
  created from the stock `kindest/node` image, not the `-gpu` custom one. Rebuild the
  image and recreate the cluster (`kind delete cluster --name kind-ai-cluster` then
  `kind create cluster --config cluster-setup/scripts/kind-config.yaml`) - the node
  image can't be swapped on a running cluster.
- **vLLM pod `Pending` forever**: check `kubectl -n llm describe pod` for
  `Insufficient memory` - the WSL2 VM's RAM allocation (`wsl -d docker-desktop free -h`)
  needs to exceed `resources.requests.memory` with room to spare for Kind's own overhead.
- **vLLM crashes immediately with a `VLLM_PORT`/URI parsing error**: `enableServiceLinks:
  false` is missing from the pod spec (should already be set - check you're on the
  current chart).
- **vLLM crashes with `UVA is not available`**: `VLLM_WSL2_ENABLE_PIN_MEMORY=1` isn't
  reaching the container, or `gpu.wsl2` is `false`. Check `kubectl -n llm exec deploy/vllm
  -- env | grep VLLM_WSL2`.
