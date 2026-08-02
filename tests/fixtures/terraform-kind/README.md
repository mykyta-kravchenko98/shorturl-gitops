# Terraform kind CI fixture

This fixture creates a disposable kind cluster, installs Argo CD, and creates
the root Application from an explicit Git repository and commit SHA. It uses a
local Terraform backend, independently of the S3 backend used by
`terraform/envs/local`.

Both source variables are intentionally required so CI cannot silently test
`main` instead of the requested commit.

```bash
terraform init
terraform apply -auto-approve \
  -var="gitops_repo_url=https://github.com/example/shorturl-gitops.git" \
  -var="target_revision=<commit-sha>"
```

Destroy the fixture even when an E2E test fails:

```bash
terraform destroy -auto-approve \
  -var="gitops_repo_url=https://github.com/example/shorturl-gitops.git" \
  -var="target_revision=<commit-sha>"
```

The local `terraform.tfstate` and `.terraform` directory are excluded by the
repository-level `.gitignore`.

