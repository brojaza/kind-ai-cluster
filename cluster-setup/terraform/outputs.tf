# Deliberately not kind_cluster.this.kubeconfig_path - see the comment on
# null_resource.argocd_root_app in argocd.tf for why that attribute goes stale.
output "kubeconfig_path" {
  description = "Path to the kubeconfig for this cluster - export KUBECONFIG to this to use kubectl/helm directly."
  value       = "${path.module}/${var.cluster_name}-config"
}

output "cluster_endpoint" {
  value = kind_cluster.this.endpoint
}

output "argocd_initial_admin_password_command" {
  description = "Run this to fetch Argo CD's initial admin password (same secret as the Helm-installed setup used)."
  value       = "kubectl --kubeconfig=${path.module}/${var.cluster_name}-config -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
