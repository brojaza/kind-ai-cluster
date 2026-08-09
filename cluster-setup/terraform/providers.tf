provider "kind" {}

# kubernetes/helm providers authenticate straight off kind_cluster's exported client
# cert - no kubeconfig file juggling needed. Both must wait for the cluster to exist
# before their credentials are meaningful, hence depending on kind_cluster.this
# everywhere below rather than relying on Terraform inferring it from the provider
# block alone.
provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}
