# Builds the GPU-enabled kind node image (prereqs/kind-gpu.Dockerfile) that cluster.tf's
# kind_cluster resource points its node `image` at - see that Dockerfile for why it's
# needed (kind's own config schema has no field to inject env vars into the node
# container directly). The manual scripts path (cluster-setup/scripts/01-*.sh) still
# requires building this by hand first; this resource is what makes `terraform apply`
# not need that manual step.
resource "docker_image" "kind_gpu_node" {
  name = "kindest/node:v1.30.0-gpu"

  build {
    context    = "${path.module}/../../prereqs"
    dockerfile = "kind-gpu.Dockerfile"
  }

  # This is a reusable base image, not disposable build output - don't delete it from
  # the local Docker daemon on `terraform destroy` (cluster.tf's kind_cluster will be
  # gone, but recreating the cluster shouldn't require rebuilding the image too).
  keep_locally = true

  triggers = {
    dockerfile_sha256 = filesha256("${path.module}/../../prereqs/kind-gpu.Dockerfile")
  }
}
