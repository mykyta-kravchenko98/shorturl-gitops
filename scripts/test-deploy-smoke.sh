#!/usr/bin/env bash
# Full disposable deploy and GitOps smoke: Terraform -> kind -> Argo CD ->
# app-of-apps -> workloads -> HTTP -> mutable Git revision. Terraform owns
# bootstrap and teardown; Chainsaw owns the condition-based Kubernetes and API
# assertions plus JUnit output.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="${repo_root}/tests/fixtures/terraform-kind"
test_dir="${repo_root}/tests/deploy-smoke"
gitops_test_dir="${repo_root}/tests/gitops-behavior"
gitops_convergence_test_dir="${gitops_test_dir}/convergence"
gitops_upgrade_test_dir="${gitops_test_dir}/upgrade"
gitops_prune_test_dir="${gitops_test_dir}/prune"
gitops_broken_image_test_dir="${gitops_test_dir}/broken-image"
gitops_recovery_test_dir="${gitops_test_dir}/recovery"
gitops_broken_manifest_test_dir="${gitops_test_dir}/broken-manifest"
gitops_controller_restart_test_dir="${gitops_test_dir}/controller-restart"
report_dir="${DEPLOY_SMOKE_REPORT_DIR:-${repo_root}/test-results/deploy-smoke}"
cluster_name="${CLUSTER_NAME:-shorturl-smoke}"
assert_timeout="${DEPLOY_SMOKE_TIMEOUT:-10m}"
kubeconfig_file=""
terraform_plan_file=""
terraform_ready=false
generated_kubeconfig="${fixture_dir}/${cluster_name}-config"

# shellcheck source=scripts/lib/gitops-test-harness.sh
source "${repo_root}/scripts/lib/gitops-test-harness.sh"

run_gitops_test() {
  local scenario_dir="$1"
  local report_name="$2"
  local value
  local -a value_args=()
  shift 2

  for value in "$@"; do
    value_args+=(--set-string "${value}")
  done

  chainsaw test "${scenario_dir}" \
    --assert-timeout "${assert_timeout}" \
    --report-format JUNIT-OPERATION \
    --report-name "${report_name}" \
    --report-path "${report_dir}" \
    "${value_args[@]}" \
    --no-color
}

refresh_gitops_apps() {
  gitops_refresh_application root
  gitops_refresh_application shorturl
}

recover_gitops_apps() {
  gitops_terminate_application_operation shorturl
  refresh_gitops_apps
}

shorturl_pod_uids() {
  kubectl -n shorturl get pods \
    --selector 'app.kubernetes.io/name=shorturl,app.kubernetes.io/component=app' \
    -o json | jq -er '
      select(.items | length > 0)
      | [.items[].metadata.uid] | sort | join(":")
    '
}

: "${GITOPS_REPO_URL:?GITOPS_REPO_URL must be the clone URL Argo CD can read}"
: "${TARGET_REVISION:?TARGET_REVISION must be a commit SHA Argo CD can fetch}"
: "${SHORTURL_SOURCE_DIR:?SHORTURL_SOURCE_DIR must point to the ShortUrl source checkout}"
KURAMA_SOURCE_DIR="${KURAMA_SOURCE_DIR:-${repo_root}/../Kurama}"
AMENOTEJIKARA_SOURCE_DIR="${AMENOTEJIKARA_SOURCE_DIR:-${repo_root}/../Amenotejikara}"

if [[ ! "${TARGET_REVISION}" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]]; then
  printf 'TARGET_REVISION must be a complete 40- or 64-character commit SHA.\n' >&2
  exit 1
fi

required_tools=(chainsaw curl docker git jq kind kubectl tar terraform)
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
if [[ ! -f "${KURAMA_SOURCE_DIR}/Dockerfile" ]]; then
  printf 'Kurama Dockerfile was not found under %s\n' \
    "${KURAMA_SOURCE_DIR}" >&2
  exit 1
fi
if [[ ! -f "${AMENOTEJIKARA_SOURCE_DIR}/Dockerfile" ]]; then
  printf 'Amenotejikara Dockerfile was not found under %s\n' \
    "${AMENOTEJIKARA_SOURCE_DIR}" >&2
  exit 1
fi

docker info >/dev/null
chainsaw lint test --file "${test_dir}/chainsaw-test.yaml"
chainsaw lint test --file "${gitops_convergence_test_dir}/chainsaw-test.yaml"
chainsaw lint test --file "${gitops_upgrade_test_dir}/chainsaw-test.yaml"
chainsaw lint test --file "${gitops_prune_test_dir}/chainsaw-test.yaml"
chainsaw lint test --file \
  "${gitops_broken_image_test_dir}/chainsaw-test.yaml"
chainsaw lint test --file "${gitops_recovery_test_dir}/chainsaw-test.yaml"
chainsaw lint test --file \
  "${gitops_broken_manifest_test_dir}/chainsaw-test.yaml"
chainsaw lint test --file \
  "${gitops_controller_restart_test_dir}/chainsaw-test.yaml"

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
  kubectl --kubeconfig "${kubeconfig_file}" get application root \
    -n argocd -o yaml >"${report_dir}/root-application.yaml" 2>&1 || true
  kubectl --kubeconfig "${kubeconfig_file}" get \
    deployments,replicasets,statefulsets,pods,jobs -A -o wide \
    >"${report_dir}/workloads.txt" 2>&1 || true
  kubectl --kubeconfig "${kubeconfig_file}" get \
    trafficscenarios.traffic.kurama.dev,credentialrotations.ops.amenotejikara.dev \
    -A -o yaml >"${report_dir}/controller-crs.yaml" 2>&1 || true
  kubectl --kubeconfig "${kubeconfig_file}" describe pods -n shorturl \
    >"${report_dir}/shorturl-pods-describe.txt" 2>&1 || true
  : >"${report_dir}/shorturl-pod-logs.txt"
  while read -r pod_name; do
    [[ -n "${pod_name}" ]] || continue
    printf '\n===== %s: current logs =====\n' "${pod_name}" \
      >>"${report_dir}/shorturl-pod-logs.txt"
    kubectl --kubeconfig "${kubeconfig_file}" logs -n shorturl \
      "${pod_name}" --all-containers --prefix \
      >>"${report_dir}/shorturl-pod-logs.txt" 2>&1 || true
    printf '\n===== %s: previous logs =====\n' "${pod_name}" \
      >>"${report_dir}/shorturl-pod-logs.txt"
    kubectl --kubeconfig "${kubeconfig_file}" logs -n shorturl \
      "${pod_name}" --all-containers --prefix --previous \
      >>"${report_dir}/shorturl-pod-logs.txt" 2>&1 || true
  done < <(
    kubectl --kubeconfig "${kubeconfig_file}" get pods -n shorturl \
      -o name 2>/dev/null
  )
  kubectl --kubeconfig "${kubeconfig_file}" get events -A --sort-by=.lastTimestamp \
    >"${report_dir}/events.txt" 2>&1 || true
}

teardown() {
  status=$?
  trap - EXIT INT TERM
  set +e

  collect_diagnostics
  rm -f "${kubeconfig_file}" "${terraform_plan_file}" \
    "${generated_kubeconfig}"

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

  gitops_harness_stop

  exit "${status}"
}
trap teardown EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Building disposable ShortUrl images...\n'
docker build --tag shorturl-ci:test "${SHORTURL_SOURCE_DIR}"
docker build --file "${SHORTURL_SOURCE_DIR}/Dockerfile.migrate" \
  --tag shorturl-migrate-ci:test "${SHORTURL_SOURCE_DIR}"
printf 'Building disposable controller images...\n'
docker build --tag kurama-ci:test "${KURAMA_SOURCE_DIR}"
docker build --tag amenotejikara-ci:test "${AMENOTEJIKARA_SOURCE_DIR}"

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
kind load docker-image --name "${cluster_name}" kurama-ci:test
kind load docker-image --name "${cluster_name}" amenotejikara-ci:test

# Locally built images have no registry-provided repoDigest. Read the imported
# manifest digest from containerd and add an explicit digest reference so CRI
# can resolve the same image when the chart switches from tag to digest.
node_image_ref="docker.io/library/shorturl-ci:test"
working_image_digest="$(docker exec "${cluster_name}-control-plane" \
  ctr --namespace k8s.io images list | awk -v image_ref="${node_image_ref}" '
    NR == 1 {
      for (column = 1; column <= NF; column++) {
        if ($column == "DIGEST") {
          digest_column = column
        }
      }
      next
    }
    $1 == image_ref && digest_column && !digest {
      digest = $digest_column
    }
    END {
      print digest
    }
  ')"
if [[ ! "${working_image_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  printf 'Could not resolve the containerd manifest digest for %s: %s\n' \
    "${node_image_ref}" "${working_image_digest}" >&2
  exit 1
fi
node_digest_ref="docker.io/library/shorturl-ci@${working_image_digest}"
docker exec "${cluster_name}-control-plane" \
  ctr --namespace k8s.io images tag "${node_image_ref}" "${node_digest_ref}"
docker exec "${cluster_name}-control-plane" \
  crictl inspecti "${node_digest_ref}" >/dev/null

printf 'Running Chainsaw deployment and HTTP assertions...\n'
chainsaw test "${test_dir}" \
  --assert-timeout "${assert_timeout}" \
  --report-format JUNIT-OPERATION \
  --report-name chainsaw-junit \
  --report-path "${report_dir}" \
  --set-string "nodeName=${cluster_name}-control-plane" \
  --no-color

printf 'Preparing a disposable Git origin for mutable GitOps revisions...\n'
gitops_harness_start "${repo_root}" "${TARGET_REVISION}" "${report_dir}"
gitops_set_root_source "${GITOPS_TEST_REPO_URL}" "${GITOPS_TEST_BRANCH}"
gitops_wait_application_source shorturl \
  "${GITOPS_TEST_REPO_URL}" "${GITOPS_TEST_BRANCH}"
gitops_wait_application_revision root "${GITOPS_TEST_REVISION}"
gitops_wait_application_revision shorturl "${GITOPS_TEST_REVISION}"

printf 'Committing a replica upgrade to the disposable Git branch...\n'
values_file="${GITOPS_TEST_WORKTREE}/helm/shorturl/values-ci.yaml"
sed -i.bak 's/^replicaCount: 1$/replicaCount: 2/' "${values_file}"
sed -i.bak \
  "0,/^  digest: \"\"$/s//  digest: \"${working_image_digest}\"/" \
  "${values_file}"
rm -f "${values_file}.bak"
if ! grep -Fxq 'replicaCount: 2' "${values_file}" || \
    ! grep -Fxq "  digest: \"${working_image_digest}\"" "${values_file}"; then
  printf 'Could not set the GitOps test replica count and working digest.\n' >&2
  exit 1
fi
gitops_harness_commit "Test GitOps replica and digest upgrade"
refresh_gitops_apps

run_gitops_test "${gitops_convergence_test_dir}" gitops-chainsaw-junit \
  "revision=${GITOPS_TEST_REVISION}"

printf 'Committing a ConfigMap rollout and prunable test resource...\n'
pre_upgrade_checksum="$(kubectl -n shorturl get deployment shorturl -o json | \
  jq -er '.spec.template.metadata.annotations["checksum/config"]')"
pre_upgrade_pods="$(shorturl_pod_uids)"
printf '\n# Mutable GitOps upgrade input.\nserver:\n  machineId: 2\n' \
  >>"${values_file}"
prunable_template="${GITOPS_TEST_WORKTREE}/helm/shorturl/templates/gitops-smoke-prunable.yaml"
cp "${gitops_test_dir}/fixtures/prunable-configmap.yaml" \
  "${prunable_template}"
gitops_harness_commit "Test ConfigMap rollout and prune fixture"
refresh_gitops_apps
run_gitops_test "${gitops_upgrade_test_dir}" gitops-upgrade-junit \
  "revision=${GITOPS_TEST_REVISION}" \
  "previousChecksum=${pre_upgrade_checksum}" \
  "previousPods=${pre_upgrade_pods}" \
  "workingDigest=${working_image_digest}"

printf 'Deleting the test resource from the next Git revision...\n'
rm -f -- "${prunable_template}"
gitops_harness_commit "Test Argo CD resource pruning"
refresh_gitops_apps
run_gitops_test "${gitops_prune_test_dir}" gitops-prune-junit \
  "revision=${GITOPS_TEST_REVISION}"

working_pods="$(shorturl_pod_uids)"
broken_image_digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"
printf 'Committing a deliberately unavailable image digest...\n'
sed -i.bak \
  "0,/^  digest: \"${working_image_digest}\"$/s//  digest: \"${broken_image_digest}\"/" \
  "${values_file}"
rm -f "${values_file}.bak"
grep -Fxq "  digest: \"${broken_image_digest}\"" "${values_file}"
gitops_harness_commit "Test unavailable ShortUrl image digest"
refresh_gitops_apps
run_gitops_test "${gitops_broken_image_test_dir}" \
  gitops-broken-image-junit \
  "revision=${GITOPS_TEST_REVISION}" \
  "brokenDigest=${broken_image_digest}" \
  "workingPods=${working_pods}"

printf 'Rolling the image digest back through Git...\n'
sed -i.bak \
  "0,/^  digest: \"${broken_image_digest}\"$/s//  digest: \"${working_image_digest}\"/" \
  "${values_file}"
rm -f "${values_file}.bak"
grep -Fxq "  digest: \"${working_image_digest}\"" "${values_file}"
gitops_harness_commit "Rollback to the working ShortUrl image digest"
recover_gitops_apps
run_gitops_test "${gitops_recovery_test_dir}" gitops-rollback-junit \
  "revision=${GITOPS_TEST_REVISION}" \
  "workingDigest=${working_image_digest}" \
  "retainedPods=${working_pods}"

stable_pods="$(shorturl_pod_uids)"
broken_template="${GITOPS_TEST_WORKTREE}/helm/shorturl/templates/gitops-smoke-broken.yaml"
printf 'Committing a manifest that the Kubernetes API rejects...\n'
cp "${gitops_test_dir}/fixtures/broken-configmap.yaml" "${broken_template}"
gitops_harness_commit "Test controlled broken manifest failure"
refresh_gitops_apps
run_gitops_test "${gitops_broken_manifest_test_dir}" \
  gitops-broken-manifest-junit \
  "revision=${GITOPS_TEST_REVISION}" \
  "stablePods=${stable_pods}"

printf 'Removing the broken manifest through Git...\n'
rm -f -- "${broken_template}"
gitops_harness_commit "Recover from the broken manifest"
recover_gitops_apps
run_gitops_test "${gitops_recovery_test_dir}" \
  gitops-manifest-recovery-junit \
  "revision=${GITOPS_TEST_REVISION}" \
  "workingDigest=${working_image_digest}" \
  "retainedPods=${stable_pods}"
gitops_wait_application_revision root "${GITOPS_TEST_REVISION}"

printf 'Installing locally built controllers from a Git revision...\n'
app_values_file="${GITOPS_TEST_WORKTREE}/helm/app-of-apps/values.yaml"
kurama_deployment_file="${GITOPS_TEST_WORKTREE}/k8s/kurama/deployment.yaml"
kurama_scenario_file="${GITOPS_TEST_WORKTREE}/k8s/kurama/shorturl-scenario.yaml"
amenotejikara_deployment_file="${GITOPS_TEST_WORKTREE}/k8s/amenotejikara/deployment.yaml"

sed -i.bak \
  's/^  controllersEnabled: false$/  controllersEnabled: true/' \
  "${app_values_file}"
rm -f "${app_values_file}.bak"
grep -Fxq '  controllersEnabled: true' "${app_values_file}"

sed -i.bak -E \
  's#528081867341\.dkr\.ecr\.eu-central-1\.amazonaws\.com/kurama@sha256:[0-9a-f]{64}#kurama-ci:test#g' \
  "${kurama_deployment_file}"
sed -i.bak 's/imagePullPolicy: IfNotPresent/imagePullPolicy: Never/' \
  "${kurama_deployment_file}"
sed -i.bak \
  '/^      imagePullSecrets:$/,/^      containers:$/ { /^      containers:$/!d; }' \
  "${kurama_deployment_file}"
sed -i.bak \
  '/KURAMA_RUNNER_IMAGE_PULL_SECRET/!b;n;s/value: ecr-pull-secret/value: ""/' \
  "${kurama_deployment_file}"
rm -f "${kurama_deployment_file}.bak"
if [[ "$(grep -Fc 'kurama-ci:test' "${kurama_deployment_file}")" != "2" ]] || \
    ! grep -Fq 'imagePullPolicy: Never' "${kurama_deployment_file}" || \
    ! grep -Fq 'value: ""' "${kurama_deployment_file}" || \
    grep -Fq 'imagePullSecrets:' "${kurama_deployment_file}"; then
  printf 'Could not prepare the Kurama controller manifest for kind.\n' >&2
  exit 1
fi

sed -i.bak -E \
  's#528081867341\.dkr\.ecr\.eu-central-1\.amazonaws\.com/amenotejikara@sha256:[0-9a-f]{64}#amenotejikara-ci:test#' \
  "${amenotejikara_deployment_file}"
sed -i.bak 's/imagePullPolicy: IfNotPresent/imagePullPolicy: Never/' \
  "${amenotejikara_deployment_file}"
sed -i.bak \
  '/^      imagePullSecrets:$/,/^      containers:$/ { /^      containers:$/!d; }' \
  "${amenotejikara_deployment_file}"
rm -f "${amenotejikara_deployment_file}.bak"
if [[ "$(grep -Fc 'amenotejikara-ci:test' \
    "${amenotejikara_deployment_file}")" != "1" ]] || \
    ! grep -Fq 'imagePullPolicy: Never' \
      "${amenotejikara_deployment_file}" || \
    grep -Fq 'imagePullSecrets:' "${amenotejikara_deployment_file}"; then
  printf 'Could not prepare the Amenotejikara controller manifest for kind.\n' \
    >&2
  exit 1
fi

sed -i.bak 's/^  replicas: 2$/  replicas: 1/' \
  "${kurama_scenario_file}"
sed -i.bak 's/^  suspend: false$/  suspend: true/' \
  "${kurama_scenario_file}"
sed -i.bak '0,/^    type: redis$/s//    type: memory/' \
  "${kurama_scenario_file}"
sed -i.bak '0,/^      type: uniform$/s//      type: fixed/' \
  "${kurama_scenario_file}"
sed -i.bak \
  's/^      minRequestsPerMinute: 2$/      requestsPerMinute: 30/' \
  "${kurama_scenario_file}"
sed -i.bak -E \
  '/^      (maxRequestsPerMinute|windowMinutes):/d' \
  "${kurama_scenario_file}"
sed -i.bak '0,/^      type: redis$/s//      type: local/' \
  "${kurama_scenario_file}"
rm -f "${kurama_scenario_file}.bak"
grep -Fxq '  replicas: 1' "${kurama_scenario_file}"
grep -Fxq '  suspend: true' "${kurama_scenario_file}"
grep -Fxq '    type: memory' "${kurama_scenario_file}"
grep -Fxq '      type: fixed' "${kurama_scenario_file}"
grep -Fxq '      requestsPerMinute: 30' "${kurama_scenario_file}"
if grep -Eq '^      (minRequestsPerMinute|maxRequestsPerMinute|windowMinutes):' \
    "${kurama_scenario_file}"; then
  printf 'Could not prepare the Kurama fixed schedule for kind.\n' >&2
  exit 1
fi
grep -Fxq '      type: local' "${kurama_scenario_file}"

gitops_harness_commit "Install controllers for restart lifecycle test"
refresh_gitops_apps
gitops_wait_application_revision kurama "${GITOPS_TEST_REVISION}"
gitops_wait_application_revision amenotejikara "${GITOPS_TEST_REVISION}"

printf 'Creating the Amenotejikara CR after its CRD is established...\n'
sed -i.bak \
  '/^  credentialRotation:$/,/^[^ ]/ s/^    enabled: false$/    enabled: true\
    pendingSecretName: postgres-credentials/' \
  "${values_file}"
rm -f "${values_file}.bak"
grep -Fxq '    enabled: true' "${values_file}"
grep -Fxq '    pendingSecretName: postgres-credentials' "${values_file}"
gitops_harness_commit "Create controller restart lifecycle CRs"
refresh_gitops_apps
gitops_refresh_application kurama
gitops_refresh_application amenotejikara
run_gitops_test "${gitops_controller_restart_test_dir}" \
  gitops-controller-restart-junit \
  "revision=${GITOPS_TEST_REVISION}"

# Restore Terraform's declared root source before checking its convergence.
printf 'Restoring the root Application to the pinned source revision...\n'
gitops_set_root_source "${GITOPS_REPO_URL}" "${TARGET_REVISION}"
gitops_wait_application_source shorturl \
  "${GITOPS_REPO_URL}" "${TARGET_REVISION}"
gitops_wait_application_revision root "${TARGET_REVISION}"
gitops_wait_application_revision shorturl "${TARGET_REVISION}"
kubectl -n shorturl rollout status deployment/shorturl --timeout=3m
if [[ "$(kubectl -n shorturl get deployment shorturl \
    -o jsonpath='{.spec.replicas}')" != "1" ]]; then
  printf 'ShortUrl did not return to the pinned replica count.\n' >&2
  exit 1
fi
gitops_harness_stop

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
