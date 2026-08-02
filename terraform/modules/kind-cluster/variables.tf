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

variable "kind_node_image" {
  description = "Digest-pinned kind node image and Kubernetes version"
  type        = string
  default     = "kindest/node:v1.31.14@sha256:6f86cf509dbb42767b6e79debc3f2c32e4ee01386f0489b3b2be24b0a55aac2b"
}

variable "shorturl_values_file" {
  description = "ShortURL Helm values overlay selected by the app-of-apps chart"
  type        = string
  default     = "values-local.yaml"
}

variable "ci_mode" {
  description = "Render only the Applications required by the disposable CI environment"
  type        = bool
  default     = false
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
