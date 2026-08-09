# Issues Open WebUI's TLS cert declaratively - see README.md's "Host-based routing"
# section. The ClusterIssuer itself (manifests/selfsigned-clusterissuer.yaml) is
# git/Argo CD-managed, not Terraform - only cert-manager's operator + CRDs are
# cluster infra here. Swapping that ClusterIssuer for an ACME/internal-CA one is the
# only change needed to reuse this exact setup on a real cluster.
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [kind_cluster.this]
}
