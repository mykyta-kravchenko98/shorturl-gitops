#!/usr/bin/env bash
# Tear the whole thing down. Since state is local and the cluster is kind,
# this leaves nothing running and nothing billing you - the point of the
# local-first setup.
set -euo pipefail

cd "$(dirname "$0")/../terraform/envs/local"
terraform destroy -auto-approve
