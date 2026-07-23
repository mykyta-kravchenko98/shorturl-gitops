# GitOps image rollback

This runbook describes how to recover from an image rollout that fails its
startup or readiness probes. The rollback changes only the immutable image
digest in `shorturl-gitops`; it does not revert CRDs, scenarios, RBAC or other
changes that may have been delivered by the same release.

## Expected failure behaviour

Kurama Deployments use the following rolling update safeguards:

- `maxUnavailable: 0`;
- `maxSurge: 1`;
- startup, liveness and readiness probes;
- `progressDeadlineSeconds: 120`;
- `revisionHistoryLimit: 5`.

When a new image is unhealthy, Kubernetes keeps the previous ready Pod
available and stops progressing the rollout. Argo CD reports the application
as `Degraded` even though it remains `Synced`: the live manifests match Git,
but the desired Deployment is unhealthy.

Confirm this state before changing Git:

```powershell
$deployment = kubectl -n shorturl get deployment kurama-manager -o json |
  ConvertFrom-Json

$deployment.status.conditions |
  Format-Table type,status,reason,message -AutoSize

kubectl -n shorturl get pods `
  -l app.kubernetes.io/name=kurama
```

The expected conditions are:

- `Available=True` with `MinimumReplicasAvailable`;
- `Progressing=False` with `ProgressDeadlineExceeded`;
- the previous Pod is ready while the new Pod is not ready.

## Find the previous working digest

Run these commands from the `shorturl-gitops` repository:

```powershell
git log -p -- k8s/kurama/deployment.yaml
```

Select the last digest that previously completed a healthy rollout. Image
digests use this form:

```text
528081867341.dkr.ecr.eu-central-1.amazonaws.com/kurama@sha256:<digest>
```

Do not select a digest only because it is older. Confirm from the Git history,
Argo CD history or a previously running ReplicaSet that it was deployed
successfully.

The image used by a running Pod can be inspected with:

```powershell
kubectl -n shorturl get pod `
  -l app.kubernetes.io/name=kurama,app.kubernetes.io/component=manager `
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}'
```

## Create an image-only rollback commit

In `k8s/kurama/deployment.yaml`, replace the failed digest with the previous
working digest in both locations:

1. `spec.template.spec.containers[name=manager].image`;
2. the `KURAMA_RUNNER_IMAGE` environment variable.

Both values must remain identical because the manager image runs the
controller while `KURAMA_RUNNER_IMAGE` defines the image of generated runner
Deployments.

Verify that only the intended image references changed:

```powershell
git diff -- k8s/kurama/deployment.yaml
git diff --check
```

The diff must not revert:

- `k8s/kurama/crd.yaml`;
- `k8s/kurama/shorturl-scenario.yaml`;
- RBAC;
- probes or rollout settings;
- unrelated applications.

Commit and push the correction:

```powershell
git add k8s/kurama/deployment.yaml
git commit -m "Rollback Kurama image to last healthy digest"
git push
```

Avoid reverting the complete automated release commit when that commit also
updated the CRD or other manifests. A dedicated image-only commit preserves
the current desired configuration while returning the executable image to a
known-good version.

## Verify recovery

Wait for Argo CD to apply the rollback commit, then run:

```powershell
kubectl -n shorturl rollout status deployment/kurama-manager --timeout=120s

kubectl -n shorturl get deployment kurama-manager `
  -o custom-columns="AVAILABLE:.status.availableReplicas,UPDATED:.status.updatedReplicas,READY:.status.readyReplicas"

kubectl -n shorturl get pods `
  -l app.kubernetes.io/name=kurama
```

The expected result is one ready manager Pod and a successfully completed
rollout. The Argo CD application should transition through `Progressing` to
`Healthy` and remain `Synced`.

The manager reconciles the `TrafficScenario` after recovery. If the failed
release also changed the runner image, verify the generated runner Deployment:

```powershell
kubectl -n shorturl rollout status deployment/shorturl-runner --timeout=120s

kubectl -n shorturl get deployment shorturl-runner `
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="runner")].image}'
```

Finally, confirm that traffic generation resumed:

```powershell
kubectl -n shorturl logs deployment/shorturl-runner `
  -c runner --tail=20
```

## Scope and limitations

This procedure is a manual GitOps rollback. Kubernetes preserves availability
and detects the failed rollout, but it does not update Git or automatically
select an older image. Argo CD self-heal also does not perform this rollback;
it continuously applies the image recorded in Git.

Automated metric-based promotion and rollback would require a progressive
delivery controller such as Argo Rollouts plus suitable health analysis. Until
that is introduced, the image-only Git commit is the source-of-truth recovery
procedure.
