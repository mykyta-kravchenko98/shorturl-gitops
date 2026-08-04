#!/usr/bin/env bash
# Validate repository-level contracts that are not covered by rendered
# Kubernetes manifests or Terraform checks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow_dir="${repo_root}/.github/workflows"
dashboard_dir="${repo_root}/k8s/grafana-dashboards"

shopt -s nullglob
workflow_files=("${workflow_dir}"/*.yml "${workflow_dir}"/*.yaml)
dashboard_files=("${dashboard_dir}"/*.json)
shopt -u nullglob

if ((${#workflow_files[@]} == 0)); then
  printf 'No GitHub Actions workflows found under %s\n' "${workflow_dir}" >&2
  exit 1
fi

printf 'Checking %d GitHub Actions workflow(s) with actionlint...\n' \
  "${#workflow_files[@]}"
actionlint -no-color "${workflow_files[@]}"

printf 'Auditing %d GitHub Actions workflow(s) with zizmor...\n' \
  "${#workflow_files[@]}"
zizmor --offline --persona=regular --strict-collection "${workflow_files[@]}"

if ((${#dashboard_files[@]} == 0)); then
  printf 'No Grafana dashboard JSON files found under %s\n' \
    "${dashboard_dir}" >&2
  exit 1
fi

printf 'Validating %d Grafana dashboard JSON file(s)...\n' \
  "${#dashboard_files[@]}"
for dashboard in "${dashboard_files[@]}"; do
  jq -e 'type == "object"' "${dashboard}" >/dev/null
  printf 'OK       %s\n' "${dashboard#"${repo_root}/"}"
done

if [[ "$(git -C "${repo_root}" rev-parse --is-shallow-repository)" == "true" ]]; then
  printf '%s\n' \
    'Gitleaks requires complete Git history; use checkout fetch-depth: 0 or unshallow the clone.' >&2
  exit 1
fi

printf 'Scanning the complete Git history with Gitleaks...\n'
gitleaks git \
  --config "${repo_root}/.gitleaks.toml" \
  --log-opts="--all" \
  --redact \
  --no-banner \
  "${repo_root}"

printf 'Repository-level static checks passed.\n'
