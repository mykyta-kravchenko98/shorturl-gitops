#!/usr/bin/env bash
set -euo pipefail
echo "ArgoCD UI: http://localhost:8081 (server.insecure=true for local dev, see terraform module)"
kubectl -n argocd port-forward svc/argocd-server 8081:80
