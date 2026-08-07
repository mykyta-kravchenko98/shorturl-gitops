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
  shift
  local output_file="${render_dir}/shorturl-${case_name}.yaml"

  printf 'Rendering Helm case: %s\n' "${case_name}"
  helm template shorturl "${shorturl_chart}" \
    --namespace shorturl \
    --kube-version "${KUBERNETES_VERSION}" \
    "$@" >"${output_file}"

  if [[ ! -s "${output_file}" ]]; then
    printf 'Helm case rendered an empty manifest: %s\n' "${case_name}" >&2
    return 1
  fi
}

render_shorturl default
render_shorturl local --values "${shorturl_chart}/values-local.yaml"
render_shorturl ci --values "${shorturl_chart}/values-ci.yaml"
render_shorturl ecr-disabled --values "${fixture_dir}/ecr-disabled.yaml"
render_shorturl external-postgres --values "${fixture_dir}/external-postgres.yaml"
render_shorturl otel-disabled --values "${fixture_dir}/otel-disabled.yaml"
render_shorturl hpa-enabled --values "${fixture_dir}/hpa-enabled.yaml"
render_shorturl ingress-enabled --values "${fixture_dir}/ingress-enabled.yaml"

# This is a cross-render contract: helm-unittest validates the annotation shape,
# while this comparison proves that changing ConfigMap input rolls the pod spec.
render_shorturl config-changed --set-string server.restPort=8586
default_checksum="$(awk '$1 == "checksum/config:" { print $2; exit }' \
  "${render_dir}/shorturl-default.yaml")"
changed_checksum="$(awk '$1 == "checksum/config:" { print $2; exit }' \
  "${render_dir}/shorturl-config-changed.yaml")"

if [[ -z "${default_checksum}" || -z "${changed_checksum}" ]]; then
  printf 'ConfigMap checksum annotation is missing\n' >&2
  exit 1
fi

if [[ "${default_checksum}" == "${changed_checksum}" ]]; then
  printf 'ConfigMap checksum did not change with its input\n' >&2
  exit 1
fi

printf 'Rendering Helm chart: app-of-apps\n'
helm template root "${app_of_apps_chart}" \
  --namespace argocd \
  --kube-version "${KUBERNETES_VERSION}" \
  >"${render_dir}/app-of-apps.yaml"

if [[ ! -s "${render_dir}/app-of-apps.yaml" ]]; then
  printf 'app-of-apps rendered an empty manifest\n' >&2
  exit 1
fi

printf 'Rendering app-of-apps controller CI profile\n'
helm template root "${app_of_apps_chart}" \
  --namespace argocd \
  --kube-version "${KUBERNETES_VERSION}" \
  --set ci.enabled=true \
  --set ci.controllersEnabled=true \
  --set kurama.externalSecret.enabled=false \
  >"${render_dir}/app-of-apps-controller-ci.yaml"
controller_ci_apps="$(awk '
  $1 == "kind:" && $2 == "Application" { application = 1; next }
  application && $1 == "name:" { print $2; application = 0 }
' "${render_dir}/app-of-apps-controller-ci.yaml" | sort | paste -sd, -)"
if [[ "${controller_ci_apps}" != \
    "amenotejikara,kurama,namespaces,shorturl" ]]; then
  printf 'Unexpected controller CI Applications: %s\n' \
    "${controller_ci_apps}" >&2
  exit 1
fi

if ! grep -Fq "\$patch: delete" \
    "${render_dir}/app-of-apps-controller-ci.yaml" || \
    ! grep -Fq 'name: shorturl-api-auth' \
      "${render_dir}/app-of-apps-controller-ci.yaml"; then
  printf 'Kurama ExternalSecret delete patch is missing from CI profile\n' >&2
  exit 1
fi

if grep -Fq "\$patch: delete" "${render_dir}/app-of-apps.yaml"; then
  printf 'Kurama ExternalSecret is unexpectedly disabled by default\n' >&2
  exit 1
fi

printf 'Helm render matrix passed.\n'
