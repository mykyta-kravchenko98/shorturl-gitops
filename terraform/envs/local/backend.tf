terraform {
  backend "s3" {
    key = "shorturl-gitops/local/terraform.tfstate"
  }
}
