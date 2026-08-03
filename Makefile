.PHONY: up down argocd-ui lint check-static-tools test-static test-helm

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
test-static: check-static-tools test-helm

test-helm:
	helm lint --strict helm/shorturl
	helm lint --strict helm/app-of-apps
	bash ./scripts/test-helm-render.sh

# Backwards-compatible local command documented since the first CI stage.
lint: test-helm
