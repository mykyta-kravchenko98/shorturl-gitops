terraform {
  required_version = ">= 1.7.0"

  backend "local" {
    path = "terraform.tfstate"
  }
}

