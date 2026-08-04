#!/usr/bin/env bash
# Full disposable deploy smoke: Terraform -> kind -> Argo CD -> app-of-apps ->
# workloads -> HTTP. Terraform owns bootstrap and teardown; Chainsaw owns the
# condition-based Kubernetes and API assertions plus JUnit output.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="${repo_root}/tests/fixtures/terraform-kind"
test_dir="${repo_root}/tests/deploy-smoke"
report_dir="${DEPLOY_SMOKE_REPORT_DIR:-${repo_root}/test-results/deploy-smoke}"
cluster_name="${CLUSTER_NAME:-shorturl-smoke}"
assert_timeout="${DEPLOY_SMOKE_TIMEOUT:-10m}"
kubeconfig_file=""
terraform_plan_file=""
terraform_ready=false

: "${GITOPS_REPO_URL:?GITOPS_REPO_URL must be the clone URL Argo CD can read}"
: "${TARGET_REVISION:?TARGET_REVISION must be a commit SHA Argo CD can fetch}"
: "${SHORTURL_SOURCE_DIR:?SHORTURL_SOURCE_DIR must point to the ShortUrl source checkout}"

if [[ ! "${TARGET_REVISION}" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]]; then
  printf 'TARGET_REVISION must be a complete 40- or 64-character commit SHA.\n' >&2
  exit 1
fi

required_tools=(chainsaw curl docker jq kind kubectl terraform)
missing_tools=()
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    missing_tools+=("${tool}")
  fi
done
if ((${#missing_tools[@]} > 0)); then
  printf 'Missing deploy-smoke tools: %s\n' "${missing_tools[*]}" >&2
  exit 1
fi

if [[ ! -f "${SHORTURL_SOURCE_DIR}/Dockerfile" || \
      ! -f "${SHORTURL_SOURCE_DIR}/Dockerfile.migrate" ]]; then
  printf 'ShortUrl Dockerfiles were not found under %s\n' "${SHORTURL_SOURCE_DIR}" >&2
  exit 1
fi

docker info >/dev/null
chainsaw lint "${test_dir}/chainsaw-test.yaml"

mkdir -p "${report_dir}"
rm -f "${report_dir}"/*.log "${report_dir}"/*.xml \
  "${report_dir}"/*.txt "${report_dir}"/*.yaml "${report_dir}"/*.tfplan
kubeconfig_file="$(mktemp)"
terraform_plan_file="$(mktemp)"

collect_diagnostics() {
  if ! kubectl --kubeconfig "${kubeconfig_file}" cluster-info >/dev/null 2>&1; then
    return
  fi
  kubectl --kubeconfig "${kubeconfig_file}" get nodes -o wide \
    >"${report_dir}/nodes.txt" 2>&1 || true
  kubectl --kubeconfig "${kubeconfig_file}" get applications -n argocd -o wide \
    >"${report_dir}/applications.txt" 2>&1 || true
  kubectl --kubeconfig "${kubeconfig_file}" get application shorturl \
    -n argocd -o yaml >"${report_dir}/shorturl-application.yaml" 2>&1 || true
  kubectl --kubeconfig "${kubeconfig_file}" get pods,jobs -A -o wide \
    >"${report_dir}/workloads.txt" 2>&1 || true
  kubectl --kubeconfig "${kubeconfig_file}" get events -A --sort-by=.lastTimestamp \
    >"${report_dir}/events.txt" 2>&1 || true
}

teardown() {
  status=$?
  trap - EXIT INT TERM
  set +e

  collect_diagnostics
  rm -f "${kubeconfig_file}" "${terraform_plan_file}"

  if [[ "${terraform_ready}" == true ]]; then
    terraform -chdir="${fixture_dir}" destroy -auto-approve -input=false \
      -var="cluster_name=${cluster_name}" \
      -var="gitops_repo_url=${GITOPS_REPO_URL}" \
      -var="target_revision=${TARGET_REVISION}" \
      >"${report_dir}/terraform-destroy.log" 2>&1
    destroy_status=$?
    if ((destroy_status != 0)); then
      printf 'terraform destroy failed; attempting kind cleanup for %s\n' \
        "${cluster_name}" >&2
      kind delete cluster --name "${cluster_name}" >> \
        "${report_dir}/terraform-destroy.log" 2>&1
      if ((status == 0)); then
        status=${destroy_status}
      fi
    fi
  fi

  exit "${status}"
}
trap teardown EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Building disposable ShortUrl images...\n'
docker build --tag shorturl-ci:test "${SHORTURL_SOURCE_DIR}"
docker build --file "${SHORTURL_SOURCE_DIR}/Dockerfile.migrate" \
  --tag shorturl-migrate-ci:test "${SHORTURL_SOURCE_DIR}"

printf 'Applying Terraform fixture for cluster %s...\n' "${cluster_name}"
terraform -chdir="${fixture_dir}" init -input=false
terraform_ready=true
terraform -chdir="${fixture_dir}" apply -auto-approve -input=false \
  -var="cluster_name=${cluster_name}" \
  -var="gitops_repo_url=${GITOPS_REPO_URL}" \
  -var="target_revision=${TARGET_REVISION}" \
  2>&1 | tee "${report_dir}/terraform-apply.log"

kind get kubeconfig --name "${cluster_name}" >"${kubeconfig_file}"
export KUBECONFIG="${kubeconfig_file}"

# The root Application is created at the end of terraform apply. Load both
# Never-pull images immediately; kubelet retries any pod scheduled meanwhile.
kind load docker-image --name "${cluster_name}" shorturl-ci:test
kind load docker-image --name "${cluster_name}" shorturl-migrate-ci:test

printf 'Running Chainsaw deployment and HTTP assertions...\n'
chainsaw test "${test_dir}" \
  --assert-timeout "${assert_timeout}" \
  --report-format JUNIT-OPERATION \
  --report-name chainsaw-junit \
  --report-path "${report_dir}" \
  --set-string "nodeName=${cluster_name}-control-plane" \
  --no-color

printf 'Checking Terraform convergence before the required second apply...\n'
set +e
terraform -chdir="${fixture_dir}" plan -detailed-exitcode -input=false \
  -var="cluster_name=${cluster_name}" \
  -var="gitops_repo_url=${GITOPS_REPO_URL}" \
  -var="target_revision=${TARGET_REVISION}" \
  -out="${terraform_plan_file}" \
  >"${report_dir}/terraform-repeat-plan.log" 2>&1
plan_status=$?
set -e

if ((plan_status == 1)); then
  printf 'Terraform convergence plan failed.\n' >&2
  exit 1
fi

terraform -chdir="${fixture_dir}" apply -auto-approve -input=false \
  -var="cluster_name=${cluster_name}" \
  -var="gitops_repo_url=${GITOPS_REPO_URL}" \
  -var="target_revision=${TARGET_REVISION}" \
  2>&1 | tee "${report_dir}/terraform-repeat-apply.log"

if ((plan_status == 2)); then
  terraform -chdir="${fixture_dir}" show -no-color \
    "${terraform_plan_file}" >"${report_dir}/terraform-unexpected-diff.txt"
  printf 'The second Terraform apply contained an unexpected diff.\n' >&2
  exit 1
fi

printf 'Deploy smoke passed; teardown will now destroy the cluster.\n'
