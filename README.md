# Qwen3-Coder-30B-A3B-Instruct on Kind, via Helm + Argo CD

> Running this on Windows (Docker Desktop + WSL2)? GPU passthrough into Kind works
> completely differently there than what's described below - see
> [docs/WINDOWS-SETUP.md](docs/WINDOWS-SETUP.md) instead.

Deploys this pipeline onto a local Kind cluster, GitOps-style:

```
Open WebUI  --OpenAI-compatible HTTP-->  vLLM  --loads-->  Qwen3-Coder-30B-A3B-Instruct
```

Two independent Helm charts (`charts/vllm`, `charts/open-webui`), each shipped as its
own Argo CD `Application`, wired together with an "app of apps" root Application.

## Read this before you start: hardware reality check

Qwen3-Coder-30B-A3B-Instruct is a 30B-parameter Mixture-of-Experts model (~3B active
per token, but all ~30B live in memory). The bf16 weights alone are **~61 GB**. That
means:

- You need a real NVIDIA GPU with a lot of VRAM reachable from Docker/Kind — realistically
  48 GB+ for comfortable headroom, or 24 GB if you switch `charts/vllm` to a quantized
  checkpoint (see "Using a quantized checkpoint" below).
- Kind ships no GPU support out of the box. You must configure the **host** (driver +
  NVIDIA Container Toolkit) yourself — see "GPU passthrough for Kind" below. This only
  works on Linux hosts (or Windows via WSL2) with an NVIDIA GPU. It does not work on
  Docker Desktop for Mac (no NVIDIA GPUs on Apple Silicon/Intel Macs) or on a plain cloud
  VM with no GPU attached.
- This project does not include a CPU-only path. vLLM is built around CUDA; running a
  model this size on CPU is not practically usable. If you don't have a GPU, either
  point `charts/vllm` at a small dense model as a smoke test, or swap vLLM for something
  CPU-friendly like Ollama/llama.cpp (out of scope for this project, but the Open WebUI
  chart works the same way against any OpenAI-compatible base URL).

Everything below assumes you've got an NVIDIA GPU on the Kind host.

## Repo layout

```
kind-config.yaml            Kind cluster definition (port mappings + GPU containerd patch)
scripts/                    Setup scripts, run in order
argocd/
  root-app.yaml              "App of apps" root Application
  apps/vllm-app.yaml          Argo CD Application -> charts/vllm
  apps/open-webui-app.yaml    Argo CD Application -> charts/open-webui
charts/
  vllm/                       Serves the model via vLLM's OpenAI-compatible API
  open-webui/                 Chat UI, points at the vllm Service
```

Both charts deploy into the `llm` namespace by default; Argo CD itself lives in `argocd`.

## Prerequisites

- Docker
- [kind](https://kind.sigs.k8s.io/) >= 0.23
- kubectl
- [Helm](https://helm.sh/) 3.x (not required for Argo CD to work, but useful for local
  testing before you push to git)
- A git repo you can push this project to (GitHub, GitLab, a local Gitea instance,
  anything Argo CD can reach). Argo CD pulls manifests from git — it does not read
  your local filesystem.
- (GPU only) NVIDIA driver + [NVIDIA Container
  Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  installed on the Kind host, and Docker's default runtime set to `nvidia`:
  ```bash
  sudo nvidia-ctk runtime configure --runtime=docker --set-as-default
  sudo systemctl restart docker
  ```

## Setup with Terraform (recommended)

`terraform/` provisions everything in "Manual setup" below except the two git-related
steps (pushing this repo, pointing Argo CD's Applications at it) - the Kind cluster
itself, Argo CD, ingress-nginx, KEDA, and cert-manager, all in one `terraform apply`.
See the comments in `terraform/*.tf` for what each resource replaces and why (notably:
Argo CD, ingress-nginx, KEDA, and cert-manager are installed via their official Helm
charts here rather than the raw-manifest approach some of the shell scripts use, both
for consistency and because Helm's release tracking sidesteps the `kubectl apply`
client-side-annotation-size bug Argo CD's own CRDs are large enough to hit).

1. [Install Terraform](https://developer.hashicorp.com/terraform/install) (or, on
   Windows with choco: `choco install terraform`).
2. Push this repo to your own git remote and point the Argo CD Applications at it -
   steps 4 and 5 under "Manual setup" below. Terraform's bootstrap step needs the
   correct `repoURL` already committed.
3. ```bash
   cd terraform
   terraform init
   terraform apply
   ```
4. Watch Argo CD take it from there: `kubectl -n argocd get applications`.

The `kind` Terraform provider can only *create* a cluster, not adopt an existing one -
if a cluster named `kind-ai-cluster` already exists (e.g. from the manual scripts
below), `terraform apply` will fail until you `kind delete cluster --name
kind-ai-cluster` first (which wipes its PVCs/state - model weights, Open WebUI
accounts, etc.).

`scripts/02-setup-gpu-support.sh` (native-Linux-only GPU device plugin, not used on
the WSL2 path this project defaults to) and `scripts/00-set-repo-url.sh` aren't part
of the Terraform config - see "GPU passthrough for Kind" and step 5 below.

## Manual setup (without Terraform)

### 1. Create the cluster

```bash
./scripts/01-create-kind-cluster.sh
```

### 2. GPU passthrough for Kind (skip only if you're doing the CPU-model smoke test)

1. Confirm the prerequisite NVIDIA Container Toolkit step above is done.
2. Uncomment the `containerdConfigPatches` block at the bottom of `kind-config.yaml`.
3. Recreate the cluster so the patch takes effect: `kind delete cluster --name kind-ai-cluster`
   then re-run step 1.
4. Install the in-cluster device plugin so nodes advertise `nvidia.com/gpu`:
   ```bash
   ./scripts/02-setup-gpu-support.sh
   ```
5. Verify: `kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.'nvidia\.com/gpu'`
   should show `1` (or however many GPUs you exposed) instead of `<none>`.

This is the fiddliest part of the whole project and behaves slightly differently across
driver/toolkit versions. If step 5 doesn't show a GPU, check `docker info | grep -i
runtime` on the host first (nvidia must be listed), then check the device plugin pod logs
with `kubectl -n kube-system logs -l name=nvidia-device-plugin-ds`.

### 3. Install Argo CD

```bash
./scripts/03-install-argocd.sh
```
This prints the initial admin password at the end. Reach the UI with:
```bash
kubectl -n argocd port-forward svc/argocd-server 8443:443
```
then open `https://localhost:8443` (self-signed cert, your browser will warn you).

For persistent access without keeping a port-forward running, install ingress-nginx
instead. Note this needs the repo pushed to git and the apps bootstrapped first (steps
4-7 below), since the actual `Ingress` resource is Argo CD-managed
(`argocd/apps/argocd-ingress-app.yaml`) rather than applied directly:
```bash
./scripts/05-install-ingress.sh
```
See "Host-based routing" below for the URL this ends up at and why.

### 4. Push this project to your own git repo

```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin <your-repo-url>
git push -u origin main
```

### 5. Point the Argo CD Applications at your repo

```bash
./scripts/00-set-repo-url.sh <your-repo-url>
git commit -am "Set repo URL"
git push
```

### 6. (Optional but recommended) Try the charts directly with Helm first

Confirms the charts themselves work before adding Argo CD's extra layer:
```bash
helm install vllm charts/vllm -n llm --create-namespace
kubectl -n llm logs -f deploy/vllm       # watch weights download + model load
helm install open-webui charts/open-webui -n llm
```
If this works, tear it down (`helm uninstall vllm open-webui -n llm`) before bootstrapping
through Argo CD, so the two don't fight over the same resources.

### 7. Bootstrap via Argo CD

```bash
./scripts/04-bootstrap-apps.sh
```
Watch it sync:
```bash
kubectl -n argocd get applications
```

### 8. Use it

vLLM takes a while on first start — it's downloading ~61 GB of weights into the PVC, then
loading them onto the GPU. Tail logs with `kubectl -n llm logs -f deploy/vllm` until you
see the Uvicorn "Application startup complete" line.

Once both pods are `Ready`, open **http://localhost:8080** (mapped from the Open WebUI
NodePort via `kind-config.yaml`). Register the first account — it becomes the admin.
The model shows up in the model picker as `Qwen3-Coder-30B-A3B-Instruct`.

## Configuration notes

### Tool calling

Qwen3-Coder is trained for agentic tool use. `charts/vllm/values.yaml` enables
`--enable-auto-tool-choice` with `--tool-call-parser qwen3_xml` (the parser vLLM's docs
currently recommend for this model). This is an actively-evolving area of vLLM — if tool
calls aren't parsing correctly on your vLLM version, check
[vLLM's tool-calling docs](https://docs.vllm.ai/en/stable/features/tool_calling/) for the
current recommended parser for this model (some older guides reference `qwen3_coder`
instead), and change `toolCalling.parser` accordingly. Set `toolCalling.enabled: false` to
turn the feature off entirely.

### Context length

The model natively supports up to 262,144 tokens, but that needs a lot of KV-cache
memory on top of the ~61 GB of weights. `charts/vllm/values.yaml` defaults
`model.maxModelLen` to `32768`, which is far more forgiving on a single local GPU. Raise
it if you have the VRAM.

Also note: this is an instruct/non-thinking model — it won't emit `<think>` blocks.

### Using a quantized checkpoint

If 61 GB of VRAM isn't available, point `model.id` in `charts/vllm/values.yaml` at a
quantized build instead of the full-precision repo, e.g. an FP8 or AWQ checkpoint from
the Qwen org or community quantizers on Hugging Face. Search the model's "Quantizations"
tab on Hugging Face for current options — this changes often enough that it isn't worth
hardcoding a specific repo id here. Prefer safetensors-based formats (FP8/AWQ/GPTQ/NVFP4)
over GGUF for vLLM specifically; vLLM's GGUF support is newer and less mature than
llama.cpp's.

### HuggingFace token

Only needed for gated models or to raise download rate limits — Qwen3 models are open.
`charts/vllm/values.yaml` has `huggingface.tokenEnabled`; set it `true` and provide
either `huggingface.token` (fine for a throwaway local cluster, but don't commit a real
token to a public repo) or `huggingface.existingSecret` pointing at a Secret you created
out-of-band with `kubectl create secret generic ... --from-literal=token=hf_xxx`
(recommended, since it keeps the token out of git entirely).

### Host-based routing

Argo CD and Open WebUI share one ingress-nginx entrypoint (`https://<host>:8443`),
dispatched by hostname rather than path - `argocd.company.test` for Argo CD,
`chat.company.test` for Open WebUI. (Pick real hostnames if you have your own domain;
these are just placeholders matching what's checked into `manifests/argocd-ingress.yaml`
and `charts/open-webui/values.yaml`'s `ingress.host`.)

Host-based instead of path-based specifically because Argo CD's `argocd` CLI needs a
real gRPC passthrough connection, which only works if nginx never terminates its TLS -
a path-based setup forces TLS termination at the ingress for every app behind it,
breaking that. Splitting by hostname lets Argo CD keep terminating its own TLS
(`ssl-passthrough`) while Open WebUI gets normal nginx-terminated TLS, on the same
port.

Setup, after `scripts/05-install-ingress.sh`:

1. Install [cert-manager](https://cert-manager.io) (issues Open WebUI's TLS cert
   declaratively - Argo CD keeps its own self-signed cert, unrelated to this):
   ```bash
   ./scripts/07-install-cert-manager.sh
   ```
2. Add both hostnames to your hosts file, pointing at `127.0.0.1` (Windows:
   `C:\Windows\System32\drivers\etc\hosts`, needs an admin-elevated editor):
   ```
   127.0.0.1  argocd.company.test
   127.0.0.1  chat.company.test
   ```
3. Push to git and let Argo CD sync (`argocd-ingress` and `open-webui` Applications).

Then Argo CD is at `https://argocd.company.test:8443` and Open WebUI at
`https://chat.company.test:8443` (both self-signed - your browser will warn you).

**Going to a real (non-local) cluster later** only touches infrastructure-provider
concerns, not anything in this repo's application config: swap the hosts-file entries
for real DNS records, swap `manifests/selfsigned-clusterissuer.yaml`'s `ClusterIssuer`
for an ACME/Let's Encrypt or internal-CA one, and swap ingress-nginx's `NodePort`
Service for `type: LoadBalancer` (or, on a managed cloud cluster, skip self-hosting
ingress-nginx entirely in favor of that cloud's native Ingress controller - e.g. the
AWS Load Balancer Controller, GKE's built-in GCE Ingress, or Azure's AGIC). The
`Ingress` objects, hostnames-as-values, and Argo CD app structure stay exactly as they
are either way.

### Scaling vLLM to zero when idle

vLLM holds the GPU/VRAM the whole time its pod is running, even with no active chat.
To free that up automatically after 5 minutes of no requests, and have it wake itself
back up on the next one, install [KEDA](https://keda.sh) and its HTTP Add-on (see
`docs/WINDOWS-SETUP.md` or [keda.sh](https://keda.sh) for what these actually are):

```bash
./scripts/06-install-keda-http.sh
```

Then flip `autoscaling.scaleToZero.enabled` to `true` in `charts/vllm/values.yaml`, and
update `backend.baseUrl` in `charts/open-webui/values.yaml` to point at the
`vllm-proxy` Service it creates instead of `vllm` directly (both files have the exact
values commented in place). Commit and push - Argo CD picks it up like any other change.

This is genuinely extra infrastructure (an operator + CRDs + a rerouted traffic path,
kept out-of-band from Argo CD the same way ingress-nginx is - see
`scripts/06-install-keda-http.sh`), and the first request after an idle period will
hang for up to a couple of minutes while vLLM reloads the model and recompiles its GPU
kernels, so it's worth it mainly if freeing the GPU between sessions matters more than
snappy wake-ups. Leave `scaleToZero.enabled: false` (the default) to skip all of this.

### Cross-chart wiring

Both charts pin `fullnameOverride` so Service names are always `vllm` and `open-webui`,
regardless of the Helm release name Argo CD assigns. `charts/open-webui/values.yaml`
points `backend.baseUrl` at `http://vllm.llm.svc.cluster.local:8000/v1` — update the
namespace in that value if you change `destination.namespace` in `argocd/apps/*.yaml`
away from the `llm` default.

## Troubleshooting

- **vLLM pod `Pending`, GPU not found**: see step 2's verification command. The pod's
  `nvidia.com/gpu` request can't schedule if no node advertises that resource.
- **vLLM pod restarts before it finishes loading**: the `startupProbe` in
  `charts/vllm/templates/deployment.yaml` gives it 30 minutes
  (`periodSeconds * failureThreshold`) before liveness checks kick in. If your disk/network
  is slow enough that even that isn't enough, raise `startupProbe.failureThreshold` in
  `values.yaml`.
- **Open WebUI shows no models**: check `kubectl -n llm logs deploy/open-webui` and
  confirm it can reach `http://vllm:8000/v1/models` from inside the cluster
  (`kubectl -n llm exec deploy/open-webui -- wget -qO- http://vllm:8000/v1/models`).
- **Argo CD app stuck `OutOfSync`/`Unknown`**: usually means it can't reach `repoURL`.
  Confirm you actually pushed to that remote and that `targetRevision: main` matches your
  default branch name.

## Cleanup

```bash
kind delete cluster --name kind-ai-cluster
```
