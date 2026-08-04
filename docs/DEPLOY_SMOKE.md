# Deploy and GitOps smoke

The deploy smoke exercises the same bootstrap path as a developer:

```text
terraform apply -> kind -> Argo CD -> root Application
  -> child Applications -> workloads -> HTTP
```

It builds the application and migration images from a ShortUrl source checkout,
loads them into a disposable kind cluster, and runs the condition-based checks
in `tests/deploy-smoke/chainsaw-test.yaml`. In CI the source checkout is pinned
to `helm/shorturl/values.yaml`'s `imageVersion`, keeping the application and
GitOps revisions aligned. Chainsaw writes a JUnit operation report. The
bootstrap script then verifies Terraform convergence and performs a second
`terraform apply`.

After the baseline passes, the same cluster exercises a mutable GitOps
revision. The test creates a temporary branch and exposes its bare repository
through a short-lived read-only `git daemon`, switches the root Application to
that branch, commits `replicaCount: 2`, and verifies that Argo CD observes the
new commit and completes the two-replica rollout. It then restores the root
Application to the original URL and SHA before checking Terraform convergence.

The assertions cover:

- a Ready kind node and an HTTP-accessible Argo CD server;
- a Synced/Healthy root Application and the complete CI child set;
- Synced/Healthy mandatory child Applications within the configured timeout;
- ready PostgreSQL, a successful migration hook, and a completed ShortUrl
  Deployment rollout;
- absence of Pending, CrashLoopBackOff, and ImagePullBackOff pods;
- `/healthz` and `/readyz` returning 200, creation and 308 resolution of a
  short link, and 404 for an unknown hash;
- a committed replica change flowing from a disposable Git revision through
  Argo CD to a healthy two-replica rollout, followed by restoration to the
  pinned revision;
- an empty convergence plan followed by a second successful Terraform apply.

The `EXIT`, `INT`, and `TERM` handlers always run `terraform destroy`. If destroy
fails, the script records the failure and attempts a direct `kind delete` as a
cleanup fallback. Cluster state and events are captured before teardown.

## Run locally

The GitOps revision must be committed and fetchable by Argo CD. From this
repository, with Docker running and a sibling ShortUrl checkout:

```bash
export GITOPS_REPO_URL="$(git remote get-url origin)"
export TARGET_REVISION="$(git rev-parse HEAD)"
export SHORTURL_SOURCE_DIR="../ShortUrl"
make test-deploy-smoke
```

Required tools are Docker, Git, tar, Terraform, kind, kubectl, Chainsaw, jq,
and curl. The temporary Git daemon listens on port `19418`; override
`GITOPS_TEST_GIT_PORT` if that port is already in use. By default the script
uses the Docker bridge gateway on Linux and `host.docker.internal` on Docker
Desktop; `GITOPS_TEST_GIT_HOST` can override that address.
`CLUSTER_NAME`, `DEPLOY_SMOKE_TIMEOUT`, and `DEPLOY_SMOKE_REPORT_DIR` can be
overridden. The default report directory is `test-results/deploy-smoke`.

CI runs the same Make target for pull requests and uploads the JUnit report,
Terraform logs, and Kubernetes diagnostics even when the smoke fails.
