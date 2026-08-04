#!/usr/bin/env bash
# Render every supported Kubernetes configuration and evaluate repository policy.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy_root="${repo_root}/policy/kubernetes"
temp_root="${TMPDIR:-/tmp}"
render_dir="$(mktemp -d "${temp_root}/shorturl-policy-test.XXXXXX")"

cleanup() {
  case "${render_dir}" in
    "${temp_root}"/shorturl-policy-test.*)
      rm -rf -- "${render_dir}"
      ;;
    *)
      printf 'Refusing to remove unexpected policy render path: %s\n' \
        "${render_dir}" >&2
      ;;
  esac
}
trap cleanup EXIT

bash "${repo_root}/scripts/render-static-manifests.sh" "${render_dir}"

printf 'Evaluating Kubernetes manifests with Conftest\n'
conftest test \
  --combine \
  --policy "${policy_root}" \
  "${render_dir}"/*.yaml \
  "${repo_root}/argocd/bootstrap/root-app.yaml" \
  "${repo_root}/k8s/namespaces.yaml"

printf 'Kubernetes policy validation passed.\n'
