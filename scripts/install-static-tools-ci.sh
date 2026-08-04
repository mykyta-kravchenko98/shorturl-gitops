#!/usr/bin/env bash
# Install the exact static-analysis toolchain into an ephemeral CI runner.
# Local developers may keep using compatible tools already present on PATH.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored to this script.
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  printf 'CI tool installation supports only Linux x86_64 runners.\n' >&2
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  printf 'mise is required; the workflow must run jdx/mise-action first.\n' >&2
  exit 1
fi

# Aqua-backed tools use the checksummed package definitions bundled with the
# pinned mise release. pipx/npm tools are pinned to exact package versions.
mise --yes use --global \
  "aqua:helm/helm@${HELM_VERSION}" \
  "aqua:kubernetes/kubectl@${KUBECTL_VERSION}" \
  "aqua:yannh/kubeconform@${KUBECONFORM_VERSION}" \
  "aqua:hashicorp/terraform@${TERRAFORM_VERSION}" \
  "aqua:terraform-linters/tflint@${TFLINT_VERSION}" \
  "pipx:checkov@${CHECKOV_VERSION}" \
  "aqua:open-policy-agent/conftest@${CONFTEST_VERSION}" \
  "aqua:rhysd/actionlint@${ACTIONLINT_VERSION}" \
  "aqua:zizmorcore/zizmor@${ZIZMOR_VERSION}" \
  "aqua:gitleaks/gitleaks@${GITLEAKS_VERSION}" \
  "aqua:jqlang/jq@${JQ_VERSION}" \
  "pipx:yamllint@${YAMLLINT_VERSION}" \
  "aqua:koalaman/shellcheck@${SHELLCHECK_VERSION}" \
  "npm:markdownlint-cli@${MARKDOWNLINT_VERSION}" \
  "aqua:hadolint/hadolint@${HADOLINT_VERSION}"

helm plugin install \
  "https://github.com/helm-unittest/helm-unittest/releases/download/v${HELM_UNITTEST_VERSION}/unittest-${HELM_UNITTEST_VERSION}.tgz"

printf 'Pinned CI static toolchain installed.\n'
