variable "cluster_name" {
  description = "Kind cluster name."
  type        = string
  default     = "kind-ai-cluster"
}

# Mirrors kind-config.yaml. NOTE: the kind provider can only CREATE a cluster, not
# adopt/modify an existing one - if a cluster named var.cluster_name already exists
# (e.g. created via scripts/01-create-kind-cluster.sh), `terraform apply` will fail.
# Delete it first (`kind delete cluster --name <name>`, which wipes its PVCs/state)
# to hand cluster lifecycle over to Terraform.
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      # Custom image = kindest/node:v1.30.0 + NVIDIA_VISIBLE_DEVICES/NVIDIA_DRIVER_CAPABILITIES
      # env vars baked in (see docs/WINDOWS-SETUP.md). Needed because Docker's "nvidia"
      # default runtime only injects the GPU into a container whose env already
      # requests it, and kind's stock node image doesn't set that.
      image = "kindest/node:v1.30.0-gpu"

      # Open WebUI - matches charts/open-webui values.yaml service.nodePort.
      # After setup, the UI is at http://localhost:8080
      extra_port_mappings {
        container_port = 30080
        host_port      = 8080
        protocol       = "TCP"
      }
      # ingress-nginx (Argo CD UI + Open WebUI, host-based routing - see README.md's
      # "Host-based routing" section). Without ingress-nginx installed and configured
      # (terraform/ingress-nginx.tf), this port just isn't listening.
      extra_port_mappings {
        container_port = 30443
        host_port      = 8443
        protocol       = "TCP"
      }
    }

    # Only relevant if charts/vllm/values.yaml has gpu.wsl2: false (native Linux path
    # with a working nvidia-container-runtime) - the WSL2 path this project actually
    # uses (gpu.wsl2: true) hostPath-mounts /dev/dxg directly instead and ignores this.
    containerd_config_patches = [
      <<-TOML
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
        privileged_without_host_devices = false
        runtime_engine = ""
        runtime_root = ""
        runtime_type = "io.containerd.runc.v2"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
        BinaryName = "/usr/bin/nvidia-container-runtime"
      TOML
    ]
  }
}
