.PHONY: up down argocd-ui lint check-static-tools

up:
	./scripts/up.sh

down:
	./scripts/down.sh

argocd-ui:
	./scripts/port-forward-argocd.sh

lint:
	helm lint helm/shorturl
	helm lint helm/app-of-apps

check-static-tools:
	bash ./scripts/check-static-tools.sh
