#!/usr/bin/env bash
# Render every supported Helm values profile without contacting a cluster.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored to this script.
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

shorturl_chart="${repo_root}/helm/shorturl"
app_of_apps_chart="${repo_root}/helm/app-of-apps"
fixture_dir="${repo_root}/tests/helm/values"
render_dir="$(mktemp -d "${TMPDIR:-/tmp}/shorturl-helm-render.XXXXXX")"

cleanup() {
  # This directory is created above and contains only the flat YAML outputs
  # named by this script. Avoid a recursive delete even for temporary data.
  rm -f -- "${render_dir}"/*.yaml
  rmdir -- "${render_dir}"
}
trap cleanup EXIT

render_shorturl() {
  local case_name="$1"
  local values_file="${2:-}"
  local output_file="${render_dir}/shorturl-${case_name}.yaml"
  local -a values_args=()

  if [[ -n "${values_file}" ]]; then
    values_args=(--values "${values_file}")
  fi

  printf 'Rendering Helm case: %s\n' "${case_name}"
  helm template shorturl "${shorturl_chart}" \
    --namespace shorturl \
    --kube-version "${KUBERNETES_VERSION}" \
    "${values_args[@]}" >"${output_file}"

  if [[ ! -s "${output_file}" ]]; then
    printf 'Helm case rendered an empty manifest: %s\n' "${case_name}" >&2
    return 1
  fi
}

render_shorturl default
render_shorturl local "${shorturl_chart}/values-local.yaml"
render_shorturl ecr-disabled "${fixture_dir}/ecr-disabled.yaml"
render_shorturl external-postgres "${fixture_dir}/external-postgres.yaml"
render_shorturl otel-disabled "${fixture_dir}/otel-disabled.yaml"
render_shorturl hpa-enabled "${fixture_dir}/hpa-enabled.yaml"
render_shorturl ingress-enabled "${fixture_dir}/ingress-enabled.yaml"
render_shorturl servicemonitor-enabled "${fixture_dir}/servicemonitor-enabled.yaml"

printf 'Rendering Helm chart: app-of-apps\n'
helm template root "${app_of_apps_chart}" \
  --namespace argocd \
  --kube-version "${KUBERNETES_VERSION}" \
  >"${render_dir}/app-of-apps.yaml"

if [[ ! -s "${render_dir}/app-of-apps.yaml" ]]; then
  printf 'app-of-apps rendered an empty manifest\n' >&2
  exit 1
fi

printf 'Helm render matrix passed.\n'
