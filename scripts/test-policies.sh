#!/usr/bin/env bash
# Render every supported Kubernetes configuration and evaluate repository policy.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored to this script.
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

shorturl_chart="${repo_root}/helm/shorturl"
app_of_apps_chart="${repo_root}/helm/app-of-apps"
fixture_dir="${repo_root}/tests/helm/values"
k8s_root="${repo_root}/k8s"
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

render_shorturl() {
  local case_name="$1"
  shift

  printf 'Rendering policy Helm case: %s\n' "${case_name}"
  helm template shorturl "${shorturl_chart}" \
    --namespace shorturl \
    --kube-version "${KUBERNETES_VERSION}" \
    "$@" >"${render_dir}/helm-shorturl-${case_name}.yaml"
}

render_shorturl default
render_shorturl local --values "${shorturl_chart}/values-local.yaml"
render_shorturl ci --values "${shorturl_chart}/values-ci.yaml"
render_shorturl ecr-disabled --values "${fixture_dir}/ecr-disabled.yaml"
render_shorturl external-postgres --values "${fixture_dir}/external-postgres.yaml"
render_shorturl otel-disabled --values "${fixture_dir}/otel-disabled.yaml"
render_shorturl hpa-enabled --values "${fixture_dir}/hpa-enabled.yaml"
render_shorturl ingress-enabled --values "${fixture_dir}/ingress-enabled.yaml"

printf 'Rendering policy Helm chart: app-of-apps\n'
helm template root "${app_of_apps_chart}" \
  --namespace argocd \
  --kube-version "${KUBERNETES_VERSION}" \
  >"${render_dir}/helm-app-of-apps.yaml"

for directory in "${k8s_root}"/*/; do
  [[ -d "${directory}" ]] || continue
  case_name="${directory%/}"
  case_name="${case_name##*/}"

  printf 'Rendering policy Kustomize case: k8s/%s\n' "${case_name}"
  kubectl kustomize "${directory}" \
    >"${render_dir}/kustomize-${case_name}.yaml"
done

for manifest in "${render_dir}"/*.yaml; do
  if [[ ! -s "${manifest}" ]]; then
    printf 'Rendered an empty policy input: %s\n' "${manifest}" >&2
    exit 1
  fi
done

printf 'Evaluating Kubernetes manifests with Conftest\n'
conftest test \
  --combine \
  --policy "${policy_root}" \
  "${render_dir}"/*.yaml \
  "${repo_root}/argocd/bootstrap/root-app.yaml" \
  "${repo_root}/k8s/namespaces.yaml"

printf 'Kubernetes policy validation passed.\n'
