output "kubeconfig_path" {
  description = "path kind wrote the kubeconfig to"
  value       = kind_cluster.this.kubeconfig_path
}

output "cluster_endpoint" {
  value = kind_cluster.this.endpoint
}

output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}
