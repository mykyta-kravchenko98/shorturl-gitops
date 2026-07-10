module "kind_cluster" {
  source = "../../modules/kind-cluster"

  cluster_name       = "shorturl"
  gitops_repo_url    = var.gitops_repo_url
  target_revision    = var.target_revision
  api_server_address = var.api_server_address
}
