#!/usr/bin/env bash
# Bring the whole stack up from nothing: kind cluster -> ArgoCD -> root app
# -> (ArgoCD takes it from there: namespaces, cert-manager, the injector,
# the collector gateway, shorturl itself).
#
# Prereqs: docker, kind, terraform, kubectl.
set -euo pipefail

cd "$(dirname "$0")/../terraform/envs/local"

if [ ! -f terraform.tfvars ]; then
  echo "No terraform.tfvars found - copy terraform.tfvars.example and set gitops_repo_url first." >&2
  exit 1
fi

terraform init
terraform apply -auto-approve

echo
echo "Cluster is up. Waiting for ArgoCD to become ready..."
kubectl -n argocd wait --for=condition=available --timeout=180s deployment/argocd-server

echo
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
echo
echo "Port-forward the UI with: ./port-forward-argocd.sh"
echo "Watch sync status with:   kubectl -n argocd get applications"
