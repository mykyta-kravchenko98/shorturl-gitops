#!/usr/bin/env bash
# Strictly validate every supported rendered and standalone Kubernetes manifest.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored to this script.
# shellcheck disable=SC1090
source "${repo_root}/tools/static-versions.env"

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

bash "${repo_root}/scripts/render-static-manifests.sh" "${render_dir}"

schema_location="${schema_root}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
kubeconform_args=(
  -strict
  -summary
  -kubernetes-version "${KUBERNETES_VERSION}"
  # Kubernetes does not publish the CRD object's own schema in the OpenAPI
  # registry. Custom resources are still validated by the vendored schemas.
  -skip CustomResourceDefinition
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
