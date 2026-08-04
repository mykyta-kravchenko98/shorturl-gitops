variable "cluster_name" {
  description = "Name of the disposable kind cluster used by CI"
  type        = string
  default     = "shorturl-ci"
}

variable "gitops_repo_url" {
  description = "Git URL Argo CD uses to clone this GitOps repository"
  type        = string
}

variable "target_revision" {
  description = "Exact Git commit SHA tested by Argo CD"
  type        = string
}

variable "http_host_port" {
  description = "Disposable cluster host port mapped to HTTP"
  type        = number
  default     = 28080
}

variable "https_host_port" {
  description = "Disposable cluster host port mapped to HTTPS"
  type        = number
  default     = 28443
}

