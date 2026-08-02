output "kubeconfig_path" {
  description = "Path to the kubeconfig generated for the disposable cluster"
  value       = module.kind_cluster.kubeconfig_path
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint of the disposable cluster"
  value       = module.kind_cluster.cluster_endpoint
}

output "argocd_namespace" {
  description = "Namespace in which Argo CD is installed"
  value       = module.kind_cluster.argocd_namespace
}

