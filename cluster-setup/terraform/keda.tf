# Scale-to-zero for vllm when idle - see README.md's "Scaling vLLM to zero when idle"
# section. The per-app HTTPScaledObject/proxy Service are chart templates
# (charts/vllm/templates/httpscaledobject.yaml), gated behind
# autoscaling.scaleToZero.enabled - only the operator + CRDs are cluster infra here.
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true

  depends_on = [kind_cluster.this]
}

resource "helm_release" "keda_http_add_on" {
  name       = "http-add-on"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda-add-ons-http"
  namespace  = "keda"

  # Needs KEDA core's CRDs to already exist.
  depends_on = [helm_release.keda]
}
