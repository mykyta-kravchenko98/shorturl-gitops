#!/usr/bin/env bash
# Build every immediate k8s/* directory without contacting a cluster.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
k8s_root="${repo_root}/k8s"
render_dir="$(mktemp -d "${TMPDIR:-/tmp}/shorturl-kustomize.XXXXXX")"

cleanup() {
  # This directory is created above and contains only flat YAML outputs.
  rm -f -- "${render_dir}"/*.yaml
  rmdir -- "${render_dir}"
}
trap cleanup EXIT

found_directory=false

for directory in "${k8s_root}"/*/; do
  [[ -d "${directory}" ]] || continue
  found_directory=true

  case_name="${directory%/}"
  case_name="${case_name##*/}"

  if [[ ! -f "${directory}/kustomization.yaml" &&
        ! -f "${directory}/kustomization.yml" &&
        ! -f "${directory}/Kustomization" ]]; then
    printf 'Missing kustomization file in k8s/%s\n' "${case_name}" >&2
    exit 1
  fi

  printf 'Building Kustomize directory: k8s/%s\n' "${case_name}"
  kubectl kustomize "${directory}" >"${render_dir}/${case_name}.yaml"

  if [[ ! -s "${render_dir}/${case_name}.yaml" ]]; then
    printf 'Kustomize directory rendered an empty manifest: k8s/%s\n' \
      "${case_name}" >&2
    exit 1
  fi
done

if [[ "${found_directory}" == false ]]; then
  printf 'No k8s/* directories found\n' >&2
  exit 1
fi

printf 'Kustomize build matrix passed.\n'
