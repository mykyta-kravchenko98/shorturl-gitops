# ShortURL Helm chart

The chart deploys the ShortURL service and supports independently selectable
database, credential, registry, and observability integrations.

## Feature switches

| Value | Resource or behavior controlled |
| --- | --- |
| `postgres.deployed` | PostgreSQL StatefulSet and Service |
| `postgres.credentials.create` | Non-production credentials Secret |
| `postgres.migrations.enabled` | Database migration Job |
| `secretsManagement.secretStore.create` | AWS SecretStore |
| `secretsManagement.externalSecret.enabled` | PostgreSQL ExternalSecret |
| `secretsManagement.credentialRotation.enabled` | CredentialRotation |
| `imagePullSecret.enabled` | Attach an existing pull Secret to workload Pods |
| `ecrRefresh.enabled` | ECR refresh RBAC, seed Job, and CronJob |
| `otel.sidecar.enabled` | OpenTelemetry sidecar and its ConfigMap |
| `metrics.serviceMonitor.enabled` | Prometheus ServiceMonitor |

The default values preserve the local AWS-backed deployment. A minimal
environment can deploy PostgreSQL while using a pre-created Kubernetes Secret
and no external controllers:

```yaml
postgres:
  deployed: true
  credentials:
    secretName: postgres-credentials
  migrations:
    enabled: true

secretsManagement:
  secretStore:
    create: false
  externalSecret:
    enabled: false
  credentialRotation:
    enabled: false

imagePullSecret:
  enabled: false

ecrRefresh:
  enabled: false

otel:
  sidecar:
    enabled: false
```

When `secretsManagement.externalSecret.enabled` and
`postgres.credentials.create` are both false, the Secret named by
`postgres.credentials.secretName` must already exist. The chart-managed Secret
is intended only for disposable environments with non-sensitive credentials.
Separating
`imagePullSecret.enabled` from `ecrRefresh.enabled` also allows a platform to
provide a pull Secret without granting the chart permission to refresh it.

The `values-ci.yaml` profile uses images named `shorturl-ci:test` and
`shorturl-migrate-ci:test` with pull policy `Never`. The CI workflow must build
and load both images into kind instead of pulling them from a registry.

## Runtime pins

All remotely pulled images owned by this chart use immutable manifest digests.
ECR refresh uses AWS CLI `2.36.9` and downloads kubectl `v1.31.14` with an
expected SHA256 checksum instead of resolving `stable.txt` at runtime. The
kubectl minor version matches the Kubernetes version used by the kind fixture.
