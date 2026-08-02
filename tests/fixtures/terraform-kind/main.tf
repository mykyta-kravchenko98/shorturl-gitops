module "kind_cluster" {
  source = "../../../terraform/modules/kind-cluster"

  cluster_name    = var.cluster_name
  gitops_repo_url = var.gitops_repo_url
  target_revision = var.target_revision

  shorturl_values_file = "values-ci.yaml"
  ci_mode              = true
}
