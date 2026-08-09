# Argo CD UI/API + Open WebUI, host-based routing - see README.md's "Host-based
# routing" section. The controller's own install is cluster infra (this file); the
# actual Ingress objects routing traffic to each app are git/Argo CD-managed
# (charts/argocd-ingress/templates/argocd-ingress.yaml, charts/open-webui/templates/ingress.yaml).
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "NodePort"
  }
  set {
    # Matches cluster-setup/scripts/kind-config.yaml's hostPort:8443 ->
    # containerPort:30443 mapping (cluster.tf here).
    name  = "controller.service.nodePorts.https"
    value = "30443"
  }
  set {
    # Required for Argo CD's combined UI/gRPC port, not a default flag - see
    # charts/argocd-ingress/templates/argocd-ingress.yaml for why ssl-passthrough is used at all.
    name  = "controller.extraArgs.enable-ssl-passthrough"
    value = "true"
  }

  depends_on = [kind_cluster.this]
}
