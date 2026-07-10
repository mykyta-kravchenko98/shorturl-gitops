# Local state on purpose: this environment is meant to be spun up/torn down
# from a single dev machine and cost $0 while off. Temp solution
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
