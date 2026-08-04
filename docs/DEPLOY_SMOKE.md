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

After the baseline passes, the same cluster exercises a mutable sequence of
GitOps revisions. The test creates a temporary branch and exposes its bare
repository through a short-lived read-only `git daemon`. The kind-loaded image
digest is read from containerd and committed with `replicaCount: 2`, proving
that Argo CD can deploy the locally built image by its immutable digest.

The remaining commits form one lifecycle:

```text
working digest and two replicas
  -> ConfigMap input change and rollout
  -> delete a Git-owned ConfigMap and prune it
  -> unavailable image digest while old Pods stay Ready
  -> restore the working digest through Git
  -> API-rejected ConfigMap and controlled SyncFailed
  -> remove the broken manifest and recover
  -> install locally built Kurama and Amenotejikara controllers
  -> restart both controller Pods and preserve CR/workload state
```

While the mutable revision is active, the test also patches the live Deployment
to three replicas and verifies that Argo CD self-heals it back to the two
replicas declared by the same Git commit. A forced synchronization of that
commit must complete without changing the Deployment generation or replacing
its Pods. Finally, the root Application returns to the original URL and SHA
before Terraform convergence is checked.

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
- live replica drift being accepted by the Kubernetes API and then self-healed
  to the value from Git without changing the synchronized revision;
- a forced repeat sync of the same revision completing successfully without a
  resource diff, Deployment spec update, or Pod replacement;
- a ConfigMap input change producing a new checksum and a complete two-replica
  rollout while the HTTP readiness endpoint remains available;
- automated pruning after a test ConfigMap is removed from the next Git
  revision;
- an unavailable digest creating a failed surge Pod while `maxUnavailable: 0`
  preserves both working Pods and HTTP availability;
- a Git rollback to the previous working digest restoring Healthy convergence
  without replacing the retained working Pods;
- an API-rejected manifest producing a `SyncFailed` operation while the current
  Deployment and HTTP endpoint remain healthy, followed by a recovery commit;
- deletion and recreation of the Kurama and Amenotejikara controller Pods
  preserving both CR `spec`/`status`, the CR UIDs, and the UIDs and readiness of
  their managed workloads;
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
and curl. Kurama and Amenotejikara source checkouts default to the sibling
`../Kurama` and `../Amenotejikara` directories; override `KURAMA_SOURCE_DIR`
and `AMENOTEJIKARA_SOURCE_DIR` when they live elsewhere. Their images are built
and loaded into kind alongside the ShortUrl images. The temporary Git daemon
listens on port `19418`; override
`GITOPS_TEST_GIT_PORT` if that port is already in use. By default the script
uses the Docker bridge gateway on Linux and `host.docker.internal` on Docker
Desktop; `GITOPS_TEST_GIT_HOST` can override that address.
`CLUSTER_NAME`, `DEPLOY_SMOKE_TIMEOUT`, and `DEPLOY_SMOKE_REPORT_DIR` can be
overridden. The default report directory is `test-results/deploy-smoke`.

CI runs the same Make target for pull requests and uploads the JUnit report,
Terraform logs, and Kubernetes diagnostics even when the smoke fails.
