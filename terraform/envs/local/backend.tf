terraform {
  required_version = ">= 1.7.0"

  backend "s3" {
    key = "shorturl-gitops/local/terraform.tfstate"
  }
}
