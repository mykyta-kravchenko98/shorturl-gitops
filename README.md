# ShortURL GitOps

GitOps infrastructure repository for the
[ShortURL](https://github.com/mykyta-kravchenko98/ShortUrl) URL shortening
service.

The project provisions a local Kubernetes cluster with `kind`, installs
Argo CD, and delegates management of the application, database, secrets,
telemetry, and custom Kubernetes controllers to it.

> This repository contains infrastructure and deployment configuration only.
> The ShortURL application and custom controller source code live in separate
> repositories.

## Architecture

```text
Terraform
  └── kind cluster
      └── Argo CD
          ├── ShortURL Helm chart
          │   ├── ShortURL
          │   ├── PostgreSQL
          │   └── OpenTelemetry sidecar
          ├── External Secrets Operator
          ├── Amenotejikara
          ├── Kurama
          └── Observability
              ├── OpenTelemetry Collector
              ├── Prometheus
              ├── Loki
              ├── Tempo
              └── Grafana
```

Argo CD uses the **app of apps** pattern: Terraform installs the root
Application, which recursively loads the declarations from `argocd/apps`.
Automated synchronization, self-healing, and pruning of obsolete resources are
enabled for the child Applications.

## Components

| Component | Purpose |
| --- | --- |
| Terraform | Creates the local `kind` cluster and installs Argo CD |
| Argo CD | Continuously synchronizes cluster state with Git |
| Helm | Deploys ShortURL, PostgreSQL, and related resources |
| External Secrets Operator | Retrieves credentials from AWS Secrets Manager |
| Amenotejikara | Performs consistent PostgreSQL credential rotation |
| Kurama | Generates background traffic from a declarative scenario |
| OpenTelemetry | Collects and routes metrics and traces |
| Prometheus, Loki, Tempo | Store metrics, logs, and traces |
| Grafana | Visualizes telemetry |

## Repository Structure

```text
.
├── argocd/
│   ├── bootstrap/       # root Argo CD Application
│   └── apps/            # child Applications
├── helm/shorturl/       # ShortURL and PostgreSQL Helm chart
├── k8s/
│   ├── amenotejikara/   # credential rotation controller
│   ├── kurama/          # traffic controller and scenario
│   └── otel-collector/  # OpenTelemetry gateway
├── terraform/
│   ├── envs/local/      # local environment
│   └── modules/         # kind cluster module
├── scripts/             # start, destroy, and port-forward scripts
└── docs/SETUP.md        # complete initial setup guide
```

## Requirements

The development environment is designed for Windows with Docker Desktop and
WSL2. Run all commands in Ubuntu inside WSL2.

Required tools:

- Docker Desktop with WSL2 integration enabled;
- Terraform 1.7 or newer;
- `kubectl`, `kind`, Helm, and `make`;
- AWS CLI v2 with a configured profile;
- at least 4 CPUs and 8 GB of memory allocated to Docker/WSL2.

The deployment also requires:

- an S3 bucket for Terraform state;
- private ECR repositories containing the application, migration, and
  controller images;
- a PostgreSQL secret in AWS Secrets Manager;
- AWS credentials in the `shorturl` namespace for ECR and Secrets Manager
  access.

See [docs/SETUP.md](docs/SETUP.md) for complete instructions on preparing a new
machine, AWS resources, and the Terraform backend.

## Quick Start

### 1. Configure Terraform

```bash
cd terraform/envs/local
cp terraform.tfvars.example terraform.tfvars
```

Verify the following values in `terraform.tfvars`:

- `gitops_repo_url` — URL of this repository;
- `target_revision` — branch tracked by Argo CD;
- `api_server_address` — defaults to `127.0.0.1`.

Initialize the S3 backend if it has not been initialized yet:

```bash
terraform init \
  -backend-config="bucket=<terraform-state-bucket>" \
  -backend-config="region=<aws-region>"
cd ../../..
```

### 2. Create the Cluster

```bash
make up
```

This command creates the `kind` cluster, installs Argo CD, and applies the root
Application. Argo CD handles the remaining deployment.

Check the cluster state:

```bash
kubectl get nodes
kubectl -n argocd get applications
kubectl get pods -A
```

Namespace-local AWS access secrets must be recreated for every new cluster.
See the
[ECR pull access section](docs/SETUP.md#4b-ecr-pull-access-for-the-cluster)
for an example.

### 3. Open Argo CD

Get the administrator password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Start port forwarding:

```bash
make argocd-ui
```

Argo CD is available at <http://localhost:8081>:

- username: `admin`;
- password: the value returned by the previous command.

### 4. Test ShortURL

```bash
kubectl -n shorturl port-forward svc/shorturl 8585:8585
```

In another terminal:

```bash
curl -i http://localhost:8585/healthz

curl -X POST http://localhost:8585/api/v1/data/shorten \
  -H 'Content-Type: application/json' \
  -d '{"longURL":"https://example.com"}'
```

## Observability

Grafana is preconfigured to use Prometheus, Loki, and Tempo.

Get the administrator password:

```bash
kubectl -n observability get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

Open Grafana:

```bash
kubectl -n observability port-forward svc/grafana 3000:80
```

The interface is available at <http://localhost:3000> with the username
`admin`.

Telemetry flow:

```text
ShortURL + OTel sidecar
        │
        ▼
OpenTelemetry Collector gateway
        ├── metrics ──► Prometheus
        └── traces  ──► Tempo

Pod logs ──► Promtail ──► Loki
```

## GitOps Workflow

To change the deployment configuration:

1. Update Helm values, a Kubernetes manifest, or an Argo CD Application.
2. Validate the configuration locally.
3. After the change reaches the tracked branch, Argo CD automatically
   synchronizes it to the cluster.

Useful commands:

```bash
# Validate the Helm chart
make lint

# Watch Argo CD Applications
kubectl -n argocd get applications -w

# Inspect ShortURL resources
kubectl -n shorturl get pods,jobs,externalsecrets,credentialrotations

# Inspect the traffic generator
kubectl -n shorturl get trafficscenarios
```

Pull requests targeting `main` are checked by MegaLinter. It validates
Terraform, Helm, Kubernetes YAML, shell scripts, Markdown, and scans for
accidentally committed secrets.

## Stopping and Destroying the Environment

Shutting down the computer does not delete the cluster. After Docker Desktop
starts again, the `kind` containers normally resume automatically.

To completely remove the local environment:

```bash
make down
```

This command runs `terraform destroy`. Local PostgreSQL data and Kubernetes
Secrets are deleted together with the cluster. Terraform state, ECR images, and
AWS Secrets Manager data remain in AWS.

## Troubleshooting

If an Application does not reach `Synced/Healthy`:

```bash
kubectl -n argocd get applications
kubectl -n shorturl get pods,jobs
kubectl -n shorturl get events --sort-by=.lastTimestamp
```

Inspect the supporting Jobs:

```bash
kubectl -n shorturl logs job/ecr-pull-refresh-seed
kubectl -n shorturl logs job/postgres-migrate
```

Common causes:

- insufficient CPU or memory allocated to Docker Desktop;
- missing AWS credentials in the `shorturl` namespace;
- an ECR token was not created or has expired;
- the configured image tag or digest does not exist in ECR;
- the PostgreSQL secret does not exist in AWS Secrets Manager;
- Argo CD is tracking the wrong repository URL or revision.

See [docs/SETUP.md](docs/SETUP.md) for more detailed instructions, including
remote LAN access to the cluster.
