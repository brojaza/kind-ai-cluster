output "kubeconfig_path" {
  description = "Path to the kubeconfig for this cluster - export KUBECONFIG to this to use kubectl/helm directly."
  value       = kind_cluster.this.kubeconfig_path
}

output "cluster_endpoint" {
  value = kind_cluster.this.endpoint
}

output "argocd_initial_admin_password_command" {
  description = "Run this to fetch Argo CD's initial admin password (same secret as the Helm-installed setup used)."
  value       = "kubectl --kubeconfig=${kind_cluster.this.kubeconfig_path} -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
