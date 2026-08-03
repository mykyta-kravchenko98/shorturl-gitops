#!/usr/bin/env bash
# Regenerate vendored custom-resource schemas from pinned or repository CRDs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
schema_root="${repo_root}/schemas/kubeconform"

kubeconform_converter_commit="02374e583d700721f57300fae78e11acd27ee539"
kubeconform_converter_sha256="d145babfbb765004030764e1b4e518bfb7a4bd7f111691a08fa57983b81881f3"
argocd_version="2.12.6"
argocd_crd_sha256="fc13177c2bccfb24c3f03795b26cd570665496d537f724fd6f9acec58e915877"
external_secrets_version="2.6.0"
external_secrets_crd_sha256="dc07cbccdd15956661d81562dd46b657e2b02e760669f3dbf2ac2f1778e27705"
pyyaml_version="6.0.3"

for required_command in curl install python3 sha256sum; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    printf 'Required schema-update command is missing: %s\n' \
      "${required_command}" >&2
    exit 1
  fi
done

temp_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${temp_root}/shorturl-schema-update.XXXXXX")"

cleanup() {
  case "${work_dir}" in
    "${temp_root}"/shorturl-schema-update.*)
      rm -rf -- "${work_dir}"
      ;;
    *)
      printf 'Refusing to remove unexpected temporary path: %s\n' \
        "${work_dir}" >&2
      ;;
  esac
}
trap cleanup EXIT

converter="${work_dir}/openapi2jsonschema.py"
argocd_crd="${work_dir}/argocd-application-crd.yaml"
external_secrets_crd="${work_dir}/external-secrets-bundle.yaml"

printf 'Downloading pinned kubeconform schema converter\n'
curl -fsSLo "${converter}" \
  "https://raw.githubusercontent.com/yannh/kubeconform/${kubeconform_converter_commit}/scripts/openapi2jsonschema.py"

printf 'Downloading Argo CD v%s Application CRD\n' "${argocd_version}"
curl -fsSLo "${argocd_crd}" \
  "https://raw.githubusercontent.com/argoproj/argo-cd/v${argocd_version}/manifests/crds/application-crd.yaml"

printf 'Downloading External Secrets v%s CRD bundle\n' \
  "${external_secrets_version}"
curl -fsSLo "${external_secrets_crd}" \
  "https://raw.githubusercontent.com/external-secrets/external-secrets/v${external_secrets_version}/deploy/crds/bundle.yaml"

printf '%s  %s\n' "${kubeconform_converter_sha256}" "${converter}" \
  | sha256sum --check --status
printf '%s  %s\n' "${argocd_crd_sha256}" "${argocd_crd}" \
  | sha256sum --check --status
printf '%s  %s\n' "${external_secrets_crd_sha256}" \
  "${external_secrets_crd}" | sha256sum --check --status

printf 'Preparing isolated schema generator\n'
python3 -m venv "${work_dir}/venv"
"${work_dir}/venv/bin/python" -m pip install \
  --disable-pip-version-check \
  "PyYAML==${pyyaml_version}"

generate_schemas() {
  local output_dir="$1"
  local crd_file="$2"

  mkdir -p "${output_dir}"
  (
    cd "${output_dir}"
    DENY_ROOT_ADDITIONAL_PROPERTIES=1 \
      "${work_dir}/venv/bin/python" "${converter}" "${crd_file}"
  )
}

generate_schemas "${work_dir}/generated/argocd" "${argocd_crd}"
generate_schemas "${work_dir}/generated/external-secrets" \
  "${external_secrets_crd}"
generate_schemas "${work_dir}/generated/amenotejikara" \
  "${repo_root}/k8s/amenotejikara/crd.yaml"
generate_schemas "${work_dir}/generated/kurama" \
  "${repo_root}/k8s/kurama/crd.yaml"

install_schema() {
  local generated_file="$1"
  local destination="$2"

  if [[ ! -s "${generated_file}" ]]; then
    printf 'Expected generated schema is missing: %s\n' \
      "${generated_file}" >&2
    exit 1
  fi

  install -m 0644 "${generated_file}" "${destination}"
}

install_schema \
  "${work_dir}/generated/argocd/application_v1alpha1.json" \
  "${schema_root}/argoproj.io/application_v1alpha1.json"
install_schema \
  "${work_dir}/generated/external-secrets/externalsecret_v1.json" \
  "${schema_root}/external-secrets.io/externalsecret_v1.json"
install_schema \
  "${work_dir}/generated/external-secrets/secretstore_v1.json" \
  "${schema_root}/external-secrets.io/secretstore_v1.json"
install_schema \
  "${work_dir}/generated/amenotejikara/credentialrotation_v1alpha1.json" \
  "${schema_root}/ops.amenotejikara.dev/credentialrotation_v1alpha1.json"
install_schema \
  "${work_dir}/generated/kurama/trafficscenario_v1alpha1.json" \
  "${schema_root}/traffic.kurama.dev/trafficscenario_v1alpha1.json"

amenotejikara_hash="$(tr -d '\r' \
  <"${repo_root}/k8s/amenotejikara/crd.yaml" | sha256sum | awk '{ print $1 }')"
kurama_hash="$(tr -d '\r' \
  <"${repo_root}/k8s/kurama/crd.yaml" | sha256sum | awk '{ print $1 }')"

printf '%s  %s\n%s  %s\n' \
  "${amenotejikara_hash}" 'k8s/amenotejikara/crd.yaml' \
  "${kurama_hash}" 'k8s/kurama/crd.yaml' \
  >"${schema_root}/local-crds.sha256"

printf 'Kubeconform custom schemas updated. Review all generated diffs.\n'
