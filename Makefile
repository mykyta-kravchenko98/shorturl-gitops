.PHONY: up down argocd-ui lint check-static-tools test-static test-deploy-smoke test-helm test-kustomize test-kubeconform test-terraform test-policies test-repository update-kubeconform-schemas

up:
	./scripts/up.sh

down:
	./scripts/down.sh

argocd-ui:
	./scripts/port-forward-argocd.sh

check-static-tools:
	bash ./scripts/check-static-tools.sh

# Aggregate only implemented checks. New static groups are added here as
# their real recipes land; no placeholder target may pass silently.
test-static: check-static-tools test-helm test-kustomize test-kubeconform test-terraform test-policies test-repository

# Requires GITOPS_REPO_URL, TARGET_REVISION and SHORTURL_SOURCE_DIR. Unlike the
# static gate this creates and always destroys a disposable kind cluster.
test-deploy-smoke:
	bash ./scripts/test-deploy-smoke.sh

test-helm:
	helm lint --strict helm/shorturl
	helm lint --strict helm/app-of-apps
	helm unittest helm/shorturl
	bash ./scripts/test-helm-render.sh

test-kustomize:
	bash ./scripts/test-kustomize.sh

test-kubeconform:
	bash ./scripts/test-kubeconform.sh

test-terraform:
	bash ./scripts/test-terraform.sh

test-policies:
	bash ./scripts/test-policies.sh

test-repository:
	bash ./scripts/test-repository.sh

# Maintenance command: downloads pinned CRDs/converter and updates vendored
# schemas. It is deliberately not part of test-static because it mutates files.
update-kubeconform-schemas:
	bash ./scripts/update-kubeconform-schemas.sh

# Backwards-compatible local command documented since the first CI stage.
lint: test-helm
