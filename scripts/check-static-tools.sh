#!/usr/bin/env bash
# Fail fast with one complete report when the local/CI static toolchain is
# incomplete or differs from the versions pinned by the repository.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored to this script.
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

errors=0

check_version() {
  local label="$1"
  local expected="$2"
  local executable="$3"
  shift 3

  if ! command -v "${executable}" >/dev/null 2>&1; then
    printf 'MISSING  %-16s expected %s (command: %s)\n' \
      "${label}" "${expected}" "${executable}"
    errors=$((errors + 1))
    return
  fi

  local output
  if ! output=$("${executable}" "$@" 2>&1); then
    printf 'ERROR    %-16s version command failed: %s %s\n' \
      "${label}" "${executable}" "$*"
    errors=$((errors + 1))
    return
  fi

  if [[ "${output}" != *"${expected}"* ]]; then
    local first_line="${output%%$'\n'*}"
    printf 'MISMATCH %-16s expected %s, got: %s\n' \
      "${label}" "${expected}" "${first_line}"
    errors=$((errors + 1))
    return
  fi

  printf 'OK       %-16s %s\n' "${label}" "${expected}"
}

check_helm_unittest() {
  if ! command -v helm >/dev/null 2>&1; then
    printf 'MISSING  %-16s expected %s (Helm is unavailable)\n' \
      "helm-unittest" "${HELM_UNITTEST_VERSION}"
    errors=$((errors + 1))
    return
  fi

  local output
  if ! output=$(helm unittest --version 2>&1); then
    printf 'MISSING  %-16s expected %s (Helm plugin: unittest)\n' \
      "helm-unittest" "${HELM_UNITTEST_VERSION}"
    errors=$((errors + 1))
    return
  fi

  if [[ "${output}" != *"${HELM_UNITTEST_VERSION}"* ]]; then
    local first_line="${output%%$'\n'*}"
    printf 'MISMATCH %-16s expected %s, got: %s\n' \
      "helm-unittest" "${HELM_UNITTEST_VERSION}" "${first_line}"
    errors=$((errors + 1))
    return
  fi

  printf 'OK       %-16s %s\n' "helm-unittest" "${HELM_UNITTEST_VERSION}"
}

check_version helm "${HELM_VERSION}" helm version --short
check_helm_unittest
check_version kubectl "${KUBECTL_VERSION}" kubectl version --client=true --output=yaml
check_version kubeconform "${KUBECONFORM_VERSION}" kubeconform -v

check_version terraform "${TERRAFORM_VERSION}" terraform version
check_version tflint "${TFLINT_VERSION}" tflint --version
check_version checkov "${CHECKOV_VERSION}" checkov --version

check_version conftest "${CONFTEST_VERSION}" conftest --version
check_version actionlint "${ACTIONLINT_VERSION}" actionlint -version
check_version zizmor "${ZIZMOR_VERSION}" zizmor --version
check_version gitleaks "${GITLEAKS_VERSION}" gitleaks version
check_version jq "${JQ_VERSION}" jq --version

check_version yamllint "${YAMLLINT_VERSION}" yamllint --version
check_version shellcheck "${SHELLCHECK_VERSION}" shellcheck --version
check_version markdownlint "${MARKDOWNLINT_VERSION}" markdownlint --version
check_version hadolint "${HADOLINT_VERSION}" hadolint --version

if ((errors > 0)); then
  printf '\nStatic toolchain check failed: %d problem(s).\n' "${errors}" >&2
  printf 'Install the pinned versions from tools/static-versions.env; see docs/STATIC_TESTS.md.\n' >&2
  exit 1
fi

printf '\nStatic toolchain matches tools/static-versions.env.\n'
