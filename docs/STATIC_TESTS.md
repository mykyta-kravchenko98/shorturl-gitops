# Static test toolchain

The complete static gate is intended to run through `make test-static` both
inside WSL2 and in CI. The gate does not deploy the application, contact a
Kubernetes cluster, or run Terraform `plan`, `apply`, or `destroy`.

CI tool versions and supported local ranges are defined in
`tools/static-versions.env`. The Makefile and test scripts never install or
upgrade tools: CI prepares them explicitly, and a developer installs them once
in WSL2. Check the local environment with:

```bash
make check-static-tools
```

The command reports every missing, incompatible, or mismatched tool in one
run. It is normal for it to fail before the static toolchain has been installed.

The Makefile exposes independent checks so a developer can run a focused group
while working on it. `make lint` remains a backwards-compatible alias:

```bash
make test-helm
make test-kustomize
make test-kubeconform
make lint
```

`make test-helm` runs strict linting, Helm unit tests, and renders the ShortURL
chart with the default, local, and CI profiles plus focused overlays for
disabled ECR refresh, external PostgreSQL, disabled OpenTelemetry, HPA,
and Ingress. The render gate also verifies that a ConfigMap input change
produces a different Deployment checksum.
It also renders the app-of-apps chart. All output is written to a temporary
directory and removed before the command exits; no cluster connection is used.

`make test-kustomize` discovers every immediate directory under `k8s/`,
requires it to contain a kustomization file, and runs `kubectl kustomize`.
Every build must produce a non-empty manifest. Rendered output is temporary,
and the command does not contact a Kubernetes cluster.

`make test-kubeconform` renders all supported Helm profiles and Kustomize
directories, then validates them together with the bootstrap and namespace
manifests. Kubernetes resources use the standard `1.31.14` schemas. Argo CD,
External Secrets Operator, CredentialRotation, and TrafficScenario use the
vendored schemas under `schemas/kubeconform/`. Strict mode is mandatory, and a
negative probe confirms that an unknown schema fails instead of being skipped.

Custom schemas are regenerated explicitly with
`make update-kubeconform-schemas`. This maintenance command is separate from
the read-only static gate because it uses the network and updates vendored
files.

`make test-static` is the aggregate entry point used locally and in CI. During
the incremental implementation of the full gate it includes only completed
checks; unfinished groups are never represented by empty targets that could
pass silently.

## Install in WSL2

CI uses the exact `*_VERSION` values from `tools/static-versions.env`. Locally,
Helm, kubectl and Terraform may use any version inside their documented
`*_LOCAL_MIN_VERSION` (inclusive) to `*_LOCAL_MAX_VERSION` (exclusive) range.
Static analyzers must match their exact pinned versions because their findings
can change between releases. Release archives and installation instructions
are published by the respective upstream projects:

| Tool | Installation source |
|---|---|
| Helm | <https://github.com/helm/helm/releases> |
| helm-unittest | <https://github.com/helm-unittest/helm-unittest/releases> |
| kubectl | <https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/> |
| kubeconform | <https://github.com/yannh/kubeconform/releases> |
| Terraform | <https://releases.hashicorp.com/terraform/> |
| TFLint | <https://github.com/terraform-linters/tflint/releases> |
| Checkov | <https://github.com/bridgecrewio/checkov/releases> |
| Conftest | <https://github.com/open-policy-agent/conftest/releases> |
| actionlint | <https://github.com/rhysd/actionlint/releases> |
| zizmor | <https://github.com/zizmorcore/zizmor/releases> |
| Gitleaks | <https://github.com/gitleaks/gitleaks/releases> |
| jq | <https://github.com/jqlang/jq/releases> |
| yamllint | <https://github.com/adrienverge/yamllint/releases> |
| ShellCheck | <https://github.com/koalaman/shellcheck/releases> |
| markdownlint-cli | <https://github.com/igorshubovych/markdownlint-cli/releases> |
| Hadolint | <https://github.com/hadolint/hadolint/releases> |

Python tools are most safely isolated with `pipx`, and the Node-based
Markdown linter can be installed with npm:

```bash
source tools/static-versions.env

pipx install "checkov==${CHECKOV_VERSION}"
pipx install "yamllint==${YAMLLINT_VERSION}"
npm install --global "markdownlint-cli@${MARKDOWNLINT_VERSION}"
```

Install the Helm plugin from its versioned release archive:

```bash
source tools/static-versions.env

helm plugin install \
  "https://github.com/helm-unittest/helm-unittest/releases/download/v${HELM_UNITTEST_VERSION}/unittest-${HELM_UNITTEST_VERSION}.tgz"
```

For the remaining standalone binaries, download the Linux archive for the
machine architecture from the linked release, verify the published checksum,
and place the executable in a directory on `PATH` such as `~/.local/bin`.
Package-manager versions are acceptable for Helm, kubectl and Terraform when
they are inside the compatible range. Analyzer versions must match exactly.

The repository deliberately accepts Helm 3 rather than moving to Helm 4 during
the static-gate work. kubectl 1.30, 1.31 and 1.32 are accepted for the kind
Kubernetes 1.31 cluster, following the supported one-minor client skew. CI uses
kubectl 1.31. Terraform accepts the current major beginning at the repository's
minimum `required_version`, while CI stays pinned to one reproducible version.

## Updating the toolchain

Update one tool at a time:

1. Change its value in `tools/static-versions.env`.
2. Update the explicit CI installation source or checksum.
3. Run `make check-static-tools` and then the complete `make test-static`.
4. Commit the version change together with any required configuration fixes.

Do not silently fall back to whatever version happens to be available on a
developer machine or a GitHub-hosted runner.
