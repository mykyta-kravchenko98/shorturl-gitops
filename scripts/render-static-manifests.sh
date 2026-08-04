#!/usr/bin/env bash
# Render the single canonical Helm/Kustomize matrix into a caller-owned directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored to this script.
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

if (( $# != 1 )); then
  printf 'Usage: %s OUTPUT_DIRECTORY\n' "${0##*/}" >&2
  exit 2
fi

output_dir="$1"
if [[ ! -d "${output_dir}" ]]; then
  printf 'Static render output directory does not exist: %s\n' \
    "${output_dir}" >&2
  exit 1
fi
shopt -s dotglob nullglob
existing_entries=("${output_dir}"/*)
if (( ${#existing_entries[@]} != 0 )); then
  printf 'Static render output directory must be empty: %s\n' \
    "${output_dir}" >&2
  exit 1
fi

shorturl_chart="${repo_root}/helm/shorturl"
app_of_apps_chart="${repo_root}/helm/app-of-apps"
fixture_dir="${repo_root}/tests/helm/values"
k8s_root="${repo_root}/k8s"

render_shorturl() {
  local case_name="$1"
  shift

  printf 'Rendering static Helm case: shorturl/%s\n' "${case_name}"
  helm template shorturl "${shorturl_chart}" \
    --namespace shorturl \
    --kube-version "${KUBERNETES_VERSION}" \
    "$@" >"${output_dir}/helm-shorturl-${case_name}.yaml"
}

render_shorturl default
render_shorturl local --values "${shorturl_chart}/values-local.yaml"
render_shorturl ci --values "${shorturl_chart}/values-ci.yaml"
render_shorturl ecr-disabled --values "${fixture_dir}/ecr-disabled.yaml"
render_shorturl external-postgres --values "${fixture_dir}/external-postgres.yaml"
render_shorturl otel-disabled --values "${fixture_dir}/otel-disabled.yaml"
render_shorturl hpa-enabled --values "${fixture_dir}/hpa-enabled.yaml"
render_shorturl ingress-enabled --values "${fixture_dir}/ingress-enabled.yaml"

printf 'Rendering static Helm chart: app-of-apps\n'
helm template root "${app_of_apps_chart}" \
  --namespace argocd \
  --kube-version "${KUBERNETES_VERSION}" \
  >"${output_dir}/helm-app-of-apps.yaml"

for directory in "${k8s_root}"/*/; do
  [[ -d "${directory}" ]] || continue
  case_name="${directory%/}"
  case_name="${case_name##*/}"

  printf 'Rendering static Kustomize case: k8s/%s\n' "${case_name}"
  kubectl kustomize "${directory}" \
    >"${output_dir}/kustomize-${case_name}.yaml"
done

for manifest in "${output_dir}"/*.yaml; do
  if [[ ! -s "${manifest}" ]]; then
    printf 'Rendered an empty static manifest: %s\n' "${manifest}" >&2
    exit 1
  fi
done
