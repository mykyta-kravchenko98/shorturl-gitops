# Setup: local kind cluster (Windows + WSL2)

Step-by-step, meant to be followed top to bottom on a fresh machine.
Written for Windows + Docker Desktop + WSL2 - **run every command below
inside a WSL2 Ubuntu shell**, not PowerShell/CMD. Native Windows and WSL2
tools don't mix well here (kubeconfig paths, shell scripts with `#!/usr/bin/
env bash`, etc.) - this repo assumes WSL2 throughout.

## 1. Install prerequisites (inside WSL2)

| Tool | Why | Check install |
|---|---|---|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) (WSL2 backend) | kind runs k8s nodes as Docker containers | `docker version` |
| Terraform >= 1.7.0 | provisions the cluster + ArgoCD | `terraform -version` |
| kubectl | talk to the cluster | `kubectl version --client` |
| kind | debugging (`kind get clusters`, `kind export logs`) | `kind version` |
| Helm | `make lint` runs `helm lint` directly | `helm version` |
| AWS CLI v2 | ECR, S3 state, IAM setup | `aws --version` |
| make | runs `Makefile` targets | `make --version` |
| Go 1.24+ | only needed if touching a controller repo locally | `go version` |

Terraform (not in Ubuntu's default apt repos):
```bash
sudo apt update && sudo apt install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

Helm:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

kind:
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

Docker: install Docker Desktop on Windows, then Settings -> Resources ->
WSL Integration -> enable the toggle for your Ubuntu distro -> Apply &
Restart. `docker version` inside WSL2 should then show a `Server:` block
(not a socket-connect error).

## 2. Configure Docker Desktop resources

Docker Desktop on the WSL2 backend doesn't expose CPU/Memory sliders in
its UI - set them via `.wslconfig` instead:
```
# C:\Users\<you>\.wslconfig
[wsl2]
memory=8GB
processors=4
```
Then `wsl --shutdown` (from PowerShell) and restart Docker Desktop.

ArgoCD (server, repo-server, application-controller, redis) plus the
collector gateway and shorturl itself (app + Postgres + sidecar) all need
to fit on one Docker Desktop VM - anything much below 4 CPU / 8GB leaves
pods `Pending`/`CrashLoopBackOff` from resource pressure.

## 3. AWS account and CLI profile

A member account inside an existing AWS Organization is fine (see
`docs/COST.md`). Create an IAM user scoped to this project rather than
reusing an admin user from another one:

1. IAM -> Users -> Create user, e.g. `shorturl-admin`.
2. Attach `AmazonEC2ContainerRegistryFullAccess` (ECR) + S3 permissions
   for the state bucket (step 3b) - tighten later if you want.
3. IAM -> Users -> that user -> Security credentials -> Create access key
   (CLI type).

```bash
aws configure --profile shorturl
# Access Key ID, Secret Access Key, region (e.g. eu-central-1), output: json
aws sts get-caller-identity --profile shorturl   # confirms the account ID
```

Set it for the rest of this session so you don't need `--profile` on
every command:
```bash
export AWS_PROFILE=shorturl
echo 'export AWS_PROFILE=shorturl' >> ~/.bashrc   # persist across shells
```

## 3b. Terraform state in S3

`terraform/envs/local/backend.tf` is `backend "s3"` with only the `key`
set (bucket/region are account-specific, supplied at `init` time, not
hardcoded in the file). Create the bucket once:

```bash
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="shorturl-tfstate-${ACCOUNT_ID}"

if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Initialize (do this once, after `terraform.tfvars` exists - step 7):
```bash
cd terraform/envs/local
terraform init -backend-config="bucket=$BUCKET" -backend-config="region=$REGION"
cd ../../..
```

If you ever see `Error: Backend configuration changed` on a later
`terraform init`: use `-migrate-state` if you have real applied resources
you want to keep, `-reconfigure` only if you're fine starting state from
scratch (it does NOT carry old state into the new backend - don't reach
for it by default).

## 4. Create the ECR repositories and push the first images

Two images come from the **ShortUrl** app repo (not this one):
`shorturl` (the app) and `shorturl-migrate` (`cmd/migrate` - SQL
migrations embedded via `go:embed`, run as a Helm hook Job here).

```bash
aws ecr create-repository --repository-name shorturl
aws ecr create-repository --repository-name shorturl-migrate
```

Pushing them is handled by CI (`ShortUrl/.github/workflows/go.yml`) via
GitHub OIDC - no manual `docker push` needed once that's set up. See
`ShortUrl/docs/CI_AWS_SETUP.md` for the one-time IAM role/trust-policy
setup, then just push to `master` and let the `image` job build+push
both images.

Update `helm/shorturl/values.yaml` (`image.repository`,
`postgres.migrateImage.repository`) to point at your account/region if
they don't already match:
```
<account-id>.dkr.ecr.<region>.amazonaws.com/shorturl
<account-id>.dkr.ecr.<region>.amazonaws.com/shorturl-migrate
```

## 4b. ECR pull access for the cluster

ECR repos are private and kind nodes have no AWS identity of their own
(unlike EKS/IRSA) - something has to mint a `docker-registry` Secret from
short-lived ECR tokens (12h lifetime) for the kubelet to use. The chart
does this itself (`helm/shorturl/templates/ecr-refresh-*.yaml`: a
pre-install seed Job + a CronJob every 10h), but it needs AWS credentials
to call `ecr:GetAuthorizationToken` - create that Secret manually, once
per cluster (NOT in git):

```bash
kubectl create secret generic aws-ecr-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) \
  --from-literal=AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) \
  -n shorturl
```
(Namespace `shorturl` needs to exist first - it's created by the
`namespaces` ArgoCD Application, which syncs before `shorturl` itself. If
this is a brand new cluster and the namespace doesn't exist yet, run
`make up` first - step 8 - then come back and run this before `shorturl`
finishes syncing, or just re-sync it afterward.)

This is cluster-local and ephemeral, same as everything else about the
kind cluster - re-create it after every `make down` + `make up`.

## 5. Push this repo to GitHub

```bash
git remote add origin https://github.com/<you>/shorturl-gitops.git
git add -A
git commit -m "initial gitops scaffold"
git push -u origin main
```

## 6. Configure the local Terraform env

```bash
cd terraform/envs/local
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
- `gitops_repo_url` -> the repo URL from step 5
- `target_revision` -> `main`
- `api_server_address` -> leave commented (127.0.0.1, this machine only),
  or set to this machine's LAN IP now if you already know you want remote
  access - see "Remote access over LAN" below either way.

## 7. Bring the cluster up

```bash
cd ../../..   # repo root
make up
```

This runs `terraform init` (reuses the S3 backend config from step 3b)
and `terraform apply`: creates the kind cluster, installs ArgoCD via Helm,
applies the root Application pointed at `argocd/apps/`.

Watch it:
```bash
kubectl -n argocd get applications -w
```
Expect `namespaces`, `otel-collector-gateway`, `shorturl` to reach
`Synced`/`Healthy`. `cert-manager` and `otel-sidecar-injector` are
intentionally **not** in `argocd/apps/` yet - they're parked in
`argocd/future/` until a controller image exists somewhere to pull from
(see "Custom controllers live in their own repos" below).

If `shorturl` sits `OutOfSync`/`Missing` with a hook stuck `Running`, check:
```bash
kubectl -n shorturl get jobs
kubectl -n shorturl logs job/ecr-pull-refresh-seed
kubectl -n shorturl logs job/postgres-migrate
```

Grab the ArgoCD admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## 8. Look at things

```bash
make argocd-ui
# http://localhost:8081, admin / password above
```

```bash
kubectl -n shorturl port-forward svc/shorturl 8585:8585
curl -i localhost:8585/healthz
curl -X POST localhost:8585/api/v1/data/shorten -d '{"longURL":"https://example.com"}'
```

Sidecar check:
```bash
kubectl -n shorturl get pod -l app.kubernetes.io/name=shorturl \
  -o jsonpath='{.items[0].spec.containers[*].name}'
# shorturl otel-collector-sidecar
```

## 9. Make a change, watch GitOps do its thing

Bump something in `helm/shorturl/values.yaml`, commit, push. Within
ArgoCD's poll interval (~3 min, or hit Sync in the UI / `argocd app sync
shorturl` with the CLI), the cluster updates itself - no `kubectl apply`.

## 10. Tear down for the day

```bash
make down
```
`terraform destroy` against the local env - kind cluster gone, Postgres
data gone with it (see `docs/COST.md`), Docker Desktop back to idle.
Nothing keeps costing money except the (tiny) ECR + S3 bills.

---

## Custom controllers live in their own repos

Decision: each custom Kubernetes controller (e.g. `otel-sidecar-injector`)
gets its **own** repository - source, `Dockerfile`, its own CI - not a
`controller/` folder inside this repo. This repo only ever holds the
*deployment* side: a Helm chart under `helm/<controller-name>/` and an
ArgoCD `Application` in `argocd/apps/` (or `argocd/future/` until its
image is published), pointing at whatever image that controller's own repo
publishes. Same pattern as `ShortUrl` itself - this repo never contains
app/controller source, only how to run it.

## Remote access over LAN

By default the kind API server only binds to `127.0.0.1`. To drive the
cluster from another device (laptop) on the same WiFi:

1. Find this machine's LAN IP: `ipconfig` (Windows, from PowerShell) ->
   "IPv4 Address" under your WiFi/Ethernet adapter.
2. In `terraform/envs/local/terraform.tfvars`:
   ```
   api_server_address = "192.168.1.50"
   ```
3. Windows Defender Firewall -> Advanced Settings -> Inbound Rules -> New
   Rule -> Port -> TCP -> `6443` (API server), `8080`, `8443` (ingress) ->
   Allow.
4. `make down` then `make up` (this only takes effect on cluster
   creation).
5. Copy the kubeconfig (`terraform output kubeconfig_path` from inside
   WSL2; to get it onto the Windows side too: `cp "$(terraform output
   -raw kubeconfig_path)" /mnt/c/Users/<you>/shorturl-kubeconfig.yaml`).
   Confirm its `server:` line reads `https://192.168.1.50:6443`, not
   `127.0.0.1`.
6. Get that exact file (not copy-pasted text - long base64 cert blocks
   get mangled by terminal line-wrapping) onto the other device: a real
   file transfer (USB, cloud drive, Telegram file attachment), not
   `cat`+paste.
7. On the other device:
   ```bash
   kubectl --kubeconfig <path> get pods -A
   kubectl --kubeconfig <path> -n argocd port-forward svc/argocd-server 8081:80
   ```
   `port-forward` tunnels through the API server itself, so it runs fine
   directly on the remote device - no need to run it on the desktop with
   `--address 0.0.0.0`.

This is fine on a trusted home network only - don't do it on untrusted
WiFi.

**DHCP caveat:** if the desktop's LAN IP changes (router reassigns it),
remote access breaks until you either reserve that IP for this machine in
the router (DHCP reservation by MAC address - the durable fix) or
`make down && make up` again with the new IP.

## What happens when you shut the PC down

Nothing is lost - Docker Desktop (and the kind containers under it) just
stop, same as any other stopped container. On power-on:
1. Start Docker Desktop, wait for "Running".
2. `docker ps -a` - kind's containers usually restart automatically
   (`unless-stopped` policy). If not: `docker start $(docker ps -a
   --filter "label=io.x-k8s.kind.cluster=shorturl" -q)`.
3. `kubectl get nodes` / `kubectl -n argocd get applications` - give it a
   minute to fully reconcile.
4. No `terraform apply` needed - nothing changed, state still matches
   reality.
5. If you set up remote access, double check the LAN IP hasn't changed
   (see DHCP caveat above).
6. The `aws-ecr-credentials` Secret and anything else that lived only in
   the (never-destroyed-here) cluster is untouched by a reboot - it's only
   `make down` (cluster destroy) that wipes it.
