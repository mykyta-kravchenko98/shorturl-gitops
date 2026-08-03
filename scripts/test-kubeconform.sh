#!/usr/bin/env bash
# Strictly validate every supported rendered and standalone Kubernetes manifest.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored to this script.
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

shorturl_chart="${repo_root}/helm/shorturl"
app_of_apps_chart="${repo_root}/helm/app-of-apps"
fixture_dir="${repo_root}/tests/helm/values"
k8s_root="${repo_root}/k8s"
schema_root="${repo_root}/schemas/kubeconform"
render_dir="$(mktemp -d "${TMPDIR:-/tmp}/shorturl-kubeconform.XXXXXX")"

cleanup() {
  # This directory is created above and contains only flat YAML outputs.
  rm -f -- "${render_dir}"/*.yaml
  rmdir -- "${render_dir}"
}
trap cleanup EXIT

printf 'Checking repository-derived CRD schema sources\n'
while read -r expected_hash crd_path; do
  [[ -n "${expected_hash}" ]] || continue
  crd_path="${crd_path%$'\r'}"
  actual_hash="$(tr -d '\r' <"${repo_root}/${crd_path}" | sha256sum | awk '{ print $1 }')"

  if [[ "${actual_hash}" != "${expected_hash}" ]]; then
    printf 'CRD schema source changed without regeneration: %s\n' \
      "${crd_path}" >&2
    exit 1
  fi
done <"${schema_root}/local-crds.sha256"

render_shorturl() {
  local case_name="$1"
  shift

  printf 'Rendering kubeconform Helm case: %s\n' "${case_name}"
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

printf 'Rendering kubeconform Helm chart: app-of-apps\n'
helm template root "${app_of_apps_chart}" \
  --namespace argocd \
  --kube-version "${KUBERNETES_VERSION}" \
  >"${render_dir}/helm-app-of-apps.yaml"

for directory in "${k8s_root}"/*/; do
  [[ -d "${directory}" ]] || continue
  case_name="${directory%/}"
  case_name="${case_name##*/}"

  printf 'Rendering kubeconform Kustomize case: k8s/%s\n' "${case_name}"
  kubectl kustomize "${directory}" \
    >"${render_dir}/kustomize-${case_name}.yaml"
done

for manifest in "${render_dir}"/*.yaml; do
  if [[ ! -s "${manifest}" ]]; then
    printf 'Rendered an empty manifest: %s\n' "${manifest}" >&2
    exit 1
  fi
done

schema_location="${schema_root}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
kubeconform_args=(
  -strict
  -summary
  -kubernetes-version "${KUBERNETES_VERSION}"
  -schema-location default
  -schema-location "${schema_location}"
)

printf 'Validating Kubernetes manifests with kubeconform\n'
kubeconform "${kubeconform_args[@]}" \
  "${render_dir}" \
  "${repo_root}/argocd/bootstrap/root-app.yaml" \
  "${repo_root}/k8s/namespaces.yaml"

# Prove that a missing schema is fatal. Never add -ignore-missing-schemas.
if printf '%s\n' \
  'apiVersion: static-gate.invalid/v1' \
  'kind: UnknownSchemaProbe' \
  'metadata:' \
  '  name: must-fail' \
  | kubeconform "${kubeconform_args[@]}" >/dev/null 2>&1; then
  printf 'kubeconform silently accepted an unknown schema\n' >&2
  exit 1
fi

printf 'Strict kubeconform validation passed.\n'
