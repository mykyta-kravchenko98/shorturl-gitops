#!/usr/bin/env bash
# Install the tools used only by the disposable deploy smoke on a Linux runner.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  printf 'CI deploy-tool installation supports only Linux x86_64 runners.\n' >&2
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  printf 'mise is required; the workflow must run jdx/mise-action first.\n' >&2
  exit 1
fi

# Aqua package metadata provides checksums for the downloaded release assets.
mise --yes use --global \
  "aqua:hashicorp/terraform@${TERRAFORM_VERSION}" \
  "aqua:kubernetes-sigs/kind@${KIND_VERSION}" \
  "aqua:kubernetes/kubectl@${KUBECTL_VERSION}" \
  "aqua:kyverno/chainsaw@${CHAINSAW_VERSION}" \
  "aqua:jqlang/jq@${JQ_VERSION}"

printf 'Pinned CI deploy-smoke toolchain installed.\n'
