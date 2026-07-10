output "kubeconfig_path" {
  value = module.kind_cluster.kubeconfig_path
}

output "cluster_endpoint" {
  value = module.kind_cluster.cluster_endpoint
}
