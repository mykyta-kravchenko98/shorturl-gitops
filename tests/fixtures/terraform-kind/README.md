# Terraform kind CI fixture

This fixture creates a disposable kind cluster, installs Argo CD, and creates
the root Application from an explicit Git repository and commit SHA. It uses a
local Terraform backend, independently of the S3 backend used by
`terraform/envs/local`.

The shared cluster module pins the kind node image to Kubernetes `v1.31.14` by
digest so local and CI runs use the same control-plane version.

Both source variables are intentionally required so CI cannot silently test
`main` instead of the requested commit. The fixture selects the ShortURL
`values-ci.yaml` overlay through the app-of-apps chart. Baseline CI mode renders
only the `namespaces` and `shorturl` child Applications. The mutable GitOps
lifecycle later opts Kurama and Amenotejikara in with locally built images;
Redis and the observability stack remain excluded from the disposable test
environment.

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

Before waiting for the ShortURL Application to become healthy, CI must build
the application and migration images and load them into this cluster as
`shorturl-ci:test` and `shorturl-migrate-ci:test`.
