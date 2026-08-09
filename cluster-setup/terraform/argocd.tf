resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  depends_on = [kind_cluster.this]
}

# Bootstraps the "app of apps" root Application - the one deliberately-imperative step
# in an otherwise GitOps-managed setup (everything else - vllm, open-webui, the
# ingress/cert-manager manifests - is then pulled from git by Argo CD itself).
#
# Deliberately NOT a kubernetes_manifest resource: that resource type validates
# against the target CRD's schema at plan time, which doesn't exist yet for a CRD
# (Application) created by helm_release.argocd in this same apply - a well-known
# chicken-and-egg gotcha with that resource type. A plain kubectl apply sidesteps it.
resource "null_resource" "argocd_root_app" {
  triggers = {
    root_app_sha = filesha256("${path.module}/../../argocd/root-app.yaml")
  }

  provisioner "local-exec" {
    # Deliberately unquoted: this repo's path has no spaces, and Windows cmd.exe
    # (Terraform's local-exec interpreter there) mangles nested quotes into doubled
    # ones - dropping them works fine cross-platform when there's no whitespace to
    # protect.
    #
    # Deliberately NOT kind_cluster.this.kubeconfig_path: that attribute is
    # ForceNew + Computed-only-once - the kind provider writes it to
    # "<cwd at apply time>/<name>-config" the first time the cluster is created and
    # never touches it again, so it goes stale (still pointing at the pre-move
    # terraform/ directory) if this module's path ever changes without recreating
    # the cluster. Recomputing it the same way the provider does, relative to
    # path.module, self-heals instead.
    command = "kubectl --kubeconfig=${path.module}/${var.cluster_name}-config apply -f ${path.module}/../../argocd/root-app.yaml"
  }

  depends_on = [helm_release.argocd]
}
