.PHONY: up down argocd-ui lint

up:
	./scripts/up.sh

down:
	./scripts/down.sh

argocd-ui:
	./scripts/port-forward-argocd.sh

lint:
	helm lint helm/shorturl
