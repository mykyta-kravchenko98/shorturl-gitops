#!/usr/bin/env bash
# Helpers for exercising Argo CD against mutable, disposable Git revisions.
# The caller owns set -euo pipefail and must call gitops_harness_stop from its
# teardown path.

GITOPS_TEST_BRANCH=""
GITOPS_TEST_REPO_URL=""
GITOPS_TEST_REVISION=""
GITOPS_TEST_WORKTREE=""
GITOPS_TEST_DAEMON_PID=""
GITOPS_TEST_TEMP_DIR=""

gitops_harness_start() {
  local source_repo="$1"
  local source_revision="$2"
  local report_dir="$3"
  local cluster_network="${4:-kind}"
  local git_host
  local git_port="${GITOPS_TEST_GIT_PORT:-19418}"
  local origin_dir
  local source_repo_abs
  local temp_parent="${TMPDIR:-/tmp}"

  GITOPS_TEST_BRANCH="gitops-smoke"
  GITOPS_TEST_TEMP_DIR="$(mktemp -d \
    "${temp_parent%/}/shorturl-gitops-smoke.XXXXXX")"
  origin_dir="${GITOPS_TEST_TEMP_DIR}/origin"
  GITOPS_TEST_WORKTREE="${GITOPS_TEST_TEMP_DIR}/worktree"
  mkdir -p "${origin_dir}" "${GITOPS_TEST_WORKTREE}"

  source_repo_abs="$(git -c "safe.directory=${source_repo}" \
    -C "${source_repo}" rev-parse --path-format=absolute --show-toplevel)"
  git -c "safe.directory=${source_repo_abs}" -C "${source_repo_abs}" \
    archive "${source_revision}" | tar -x -C "${GITOPS_TEST_WORKTREE}"
  git -C "${GITOPS_TEST_WORKTREE}" init \
    --initial-branch="${GITOPS_TEST_BRANCH}" >/dev/null
  git -C "${GITOPS_TEST_WORKTREE}" config user.name "GitOps smoke"
  git -C "${GITOPS_TEST_WORKTREE}" config user.email \
    "gitops-smoke@example.invalid"
  git -C "${GITOPS_TEST_WORKTREE}" add --all
  git -C "${GITOPS_TEST_WORKTREE}" commit \
    --message "Baseline from ${source_revision}" >/dev/null
  GITOPS_TEST_REVISION="$(git -C "${GITOPS_TEST_WORKTREE}" rev-parse HEAD)"
  git clone --bare "${GITOPS_TEST_WORKTREE}" \
    "${origin_dir}/shorturl-gitops.git" >/dev/null
  git -C "${GITOPS_TEST_WORKTREE}" remote add origin \
    "${origin_dir}/shorturl-gitops.git"
  git -C "${GITOPS_TEST_WORKTREE}" push --set-upstream origin \
    "${GITOPS_TEST_BRANCH}" >/dev/null

  git daemon \
    --reuseaddr \
    --base-path="${origin_dir}" \
    --export-all \
    --informative-errors \
    --verbose \
    --listen=0.0.0.0 \
    --port="${git_port}" \
    "${origin_dir}" >"${report_dir}/git-daemon.log" 2>&1 &
  GITOPS_TEST_DAEMON_PID=$!

  # Docker Desktop exposes the host through a stable DNS name, including when
  # the caller itself runs under WSL and therefore reports uname=Linux.
  # Native Linux uses the IPv4 bridge gateway; dual-stack networks may list
  # their IPv6 gateway first, while git daemon below intentionally binds IPv4.
  if [[ -n "${GITOPS_TEST_GIT_HOST:-}" ]]; then
    git_host="${GITOPS_TEST_GIT_HOST}"
  elif docker info --format '{{.OperatingSystem}}' 2>/dev/null | \
      grep -Fqi 'Docker Desktop'; then
    git_host="host.docker.internal"
  elif [[ "$(uname -s)" == "Linux" ]]; then
    git_host="$(docker network inspect "${cluster_network}" | jq -r '
      .[0].IPAM.Config[]
      | select(.Gateway | contains(":") | not)
      | .Gateway
    ' | head -n 1)"
  else
    git_host="host.docker.internal"
  fi
  if [[ -z "${git_host}" ]]; then
    printf 'Could not resolve the Docker host for the GitOps test origin.\n' >&2
    return 1
  fi

  GITOPS_TEST_REPO_URL="git://${git_host}:${git_port}/shorturl-gitops.git"

  # Verify the same path Argo CD will use, rather than only checking the
  # daemon from the host running the test.
  for _ in $(seq 1 30); do
    if ! kill -0 "${GITOPS_TEST_DAEMON_PID}" >/dev/null 2>&1; then
      printf 'Disposable git daemon exited unexpectedly.\n' >&2
      return 1
    fi
    if kubectl -n argocd exec deployment/argocd-repo-server -- \
      git ls-remote "${GITOPS_TEST_REPO_URL}" \
        "refs/heads/${GITOPS_TEST_BRANCH}" 2>/dev/null | \
        grep -Fq "${GITOPS_TEST_REVISION}"; then
      return 0
    fi
    sleep 1
  done

  printf 'Argo CD repo-server cannot read the disposable Git origin %s.\n' \
    "${GITOPS_TEST_REPO_URL}" >&2
  return 1
}

gitops_harness_commit() {
  local message="$1"

  if git -C "${GITOPS_TEST_WORKTREE}" diff --quiet && \
      git -C "${GITOPS_TEST_WORKTREE}" diff --cached --quiet; then
    printf 'The GitOps test revision has no changes to commit.\n' >&2
    return 1
  fi

  git -C "${GITOPS_TEST_WORKTREE}" add --all
  git -C "${GITOPS_TEST_WORKTREE}" commit --message "${message}" >/dev/null
  git -C "${GITOPS_TEST_WORKTREE}" push origin \
    "${GITOPS_TEST_BRANCH}" >/dev/null
  GITOPS_TEST_REVISION="$(git -C "${GITOPS_TEST_WORKTREE}" rev-parse HEAD)"
}

gitops_set_root_source() {
  local repo_url="$1"
  local revision="$2"
  local source_patch

  # The test operations make the app-of-apps parameter ordering an explicit
  # contract. If the Terraform template changes, fail before replacing the
  # wrong parameter instead of silently producing invalid child Applications.
  source_patch="$(jq -cn \
    --arg repo_url "${repo_url}" \
    --arg revision "${revision}" '
      [
        {
          op: "replace",
          path: "/spec/source/repoURL",
          value: $repo_url
        },
        {
          op: "replace",
          path: "/spec/source/targetRevision",
          value: $revision
        },
        {
          op: "test",
          path: "/spec/source/helm/parameters/0/name",
          value: "git.repoURL"
        },
        {
          op: "replace",
          path: "/spec/source/helm/parameters/0/value",
          value: $repo_url
        },
        {
          op: "test",
          path: "/spec/source/helm/parameters/1/name",
          value: "git.targetRevision"
        },
        {
          op: "replace",
          path: "/spec/source/helm/parameters/1/value",
          value: $revision
        }
      ]
    ')"
  kubectl -n argocd patch application root --type json \
    --patch "${source_patch}" >/dev/null
  gitops_refresh_application root
}

gitops_refresh_application() {
  local application="$1"

  kubectl -n argocd annotate application "${application}" \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

gitops_wait_application_source() {
  local application="$1"
  local repo_url="$2"
  local revision="$3"

  for _ in $(seq 1 120); do
    if kubectl -n argocd get application "${application}" -o json | jq -e \
      --arg repo_url "${repo_url}" \
      --arg revision "${revision}" '
        .spec.source.repoURL == $repo_url and
        .spec.source.targetRevision == $revision
      ' >/dev/null; then
      return 0
    fi
    sleep 1
  done

  printf 'Application %s did not switch to %s at %s.\n' \
    "${application}" "${repo_url}" "${revision}" >&2
  return 1
}

gitops_wait_application_revision() {
  local application="$1"
  local revision="$2"

  for _ in $(seq 1 180); do
    if kubectl -n argocd get application "${application}" -o json | jq -e \
      --arg revision "${revision}" '
        .status.sync.revision == $revision and
        .status.sync.status == "Synced" and
        .status.health.status == "Healthy"
      ' >/dev/null; then
      return 0
    fi
    sleep 1
  done

  printf 'Application %s did not become Synced/Healthy at revision %s.\n' \
    "${application}" "${revision}" >&2
  return 1
}

gitops_harness_stop() {
  if [[ -n "${GITOPS_TEST_DAEMON_PID}" ]]; then
    kill "${GITOPS_TEST_DAEMON_PID}" >/dev/null 2>&1 || true
    wait "${GITOPS_TEST_DAEMON_PID}" >/dev/null 2>&1 || true
    GITOPS_TEST_DAEMON_PID=""
  fi
  if [[ -n "${GITOPS_TEST_TEMP_DIR}" ]]; then
    case "${GITOPS_TEST_TEMP_DIR##*/}" in
      shorturl-gitops-smoke.*)
        rm -rf -- "${GITOPS_TEST_TEMP_DIR}"
        ;;
      *)
        printf 'Refusing to remove unexpected harness path %s.\n' \
          "${GITOPS_TEST_TEMP_DIR}" >&2
        return 1
        ;;
    esac
    GITOPS_TEST_TEMP_DIR=""
    GITOPS_TEST_WORKTREE=""
  fi
}
