#!/usr/bin/env bash
# Run the read-only Terraform static gate without contacting the configured backend.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${temp_root}/shorturl-terraform-test.XXXXXX")"

cleanup() {
  case "${work_dir}" in
    "${temp_root}"/shorturl-terraform-test.*)
      rm -rf -- "${work_dir}"
      ;;
    *)
      printf 'Refusing to remove unexpected Terraform test path: %s\n' \
        "${work_dir}" >&2
      ;;
  esac
}
trap cleanup EXIT

terraform_roots=(
  "terraform/envs/local"
  "tests/fixtures/terraform-kind"
)

for relative_root in "${terraform_roots[@]}"; do
  root="${repo_root}/${relative_root}"
  if [[ ! -d "${root}" ]]; then
    printf 'Terraform root does not exist: %s\n' "${relative_root}" >&2
    exit 1
  fi
  if [[ ! -f "${root}/.terraform.lock.hcl" ]]; then
    printf 'Terraform root has no committed provider lock file: %s\n' \
      "${relative_root}" >&2
    exit 1
  fi
done

mapfile -d '' terraform_files < <(
  find "${repo_root}/terraform" "${repo_root}/tests/fixtures" \
    -type f -name '*.tf' \
    -not -path '*/.terraform/*' \
    -print0
)

if (( ${#terraform_files[@]} == 0 )); then
  printf 'No Terraform files were discovered.\n' >&2
  exit 1
fi

printf 'Checking Terraform formatting\n'
terraform fmt -check -diff "${terraform_files[@]}"

for relative_root in "${terraform_roots[@]}"; do
  root="${repo_root}/${relative_root}"
  data_dir="${work_dir}/${relative_root//\//_}"
  mkdir -p "${data_dir}"

  printf 'Initializing Terraform root without backend: %s\n' "${relative_root}"
  TF_DATA_DIR="${data_dir}" terraform -chdir="${root}" init \
    -backend=false \
    -input=false \
    -lockfile=readonly \
    -no-color

  printf 'Validating Terraform root: %s\n' "${relative_root}"
  TF_DATA_DIR="${data_dir}" terraform -chdir="${root}" validate -no-color
done

mapfile -t terraform_dirs < <(
  find "${repo_root}/terraform" "${repo_root}/tests/fixtures" \
    -type f -name '*.tf' \
    -not -path '*/.terraform/*' \
    -printf '%h\n' \
    | sort -u
)

printf 'Running TFLint in every Terraform directory\n'
for terraform_dir in "${terraform_dirs[@]}"; do
  printf 'Linting Terraform directory: %s\n' \
    "${terraform_dir#"${repo_root}/"}"
  tflint \
    --chdir="${terraform_dir}" \
    --config="${repo_root}/.tflint.hcl" \
    --format=compact \
    --no-color
done

printf 'Running Checkov against Terraform configuration\n'
checkov \
  --directory "${repo_root}/terraform" \
  --framework terraform \
  --quiet \
  --compact
checkov \
  --directory "${repo_root}/tests/fixtures/terraform-kind" \
  --framework terraform \
  --quiet \
  --compact

printf 'Terraform static validation passed.\n'
