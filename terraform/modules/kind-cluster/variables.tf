variable "cluster_name" {
  description = "kind cluster name"
  type        = string
  default     = "shorturl"
}

variable "worker_count" {
  description = "number of kind worker nodes (0 = single control-plane node runs everything)"
  type        = number
  default     = 0
}

variable "argocd_chart_version" {
  description = "argo-cd helm chart version"
  type        = string
  default     = "7.6.12"
}

variable "gitops_repo_url" {
  description = "URL of this gitops repo, as ArgoCD will clone it"
  type        = string
}

variable "target_revision" {
  description = "git branch/tag ArgoCD tracks"
  type        = string
  default     = "main"
}

variable "api_server_address" {
  description = <<-EOT
    IP the kind API server binds to. "127.0.0.1" (default) means only this
    machine can reach the cluster. Set it to this machine's LAN IP to drive
    the cluster from another device on the same network (see
    docs/SETUP.md).
  EOT
  type        = string
  default     = "127.0.0.1"
}
