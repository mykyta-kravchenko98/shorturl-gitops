variable "gitops_repo_url" {
  description = "URL of this gitops repo (e.g. https://github.com/<you>/shorturl-gitops.git)"
  type        = string
}

variable "target_revision" {
  type    = string
  default = "main"
}

variable "api_server_address" {
  description = "Set to this machine's LAN IP to drive the cluster from another device (see docs/SETUP.md). Leave as 127.0.0.1 if you only ever use this machine directly."
  type        = string
  default     = "127.0.0.1"
}
