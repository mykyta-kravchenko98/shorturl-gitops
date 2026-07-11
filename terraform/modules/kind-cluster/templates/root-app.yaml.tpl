apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${repo_url}
    targetRevision: ${target_revision}
    path: argocd/apps
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
  # `directory.recurse: false` on child Applications (e.g. namespaces.yaml)
  # can't be told apart from "not set" once round-tripped through the
  # Application CRD (omitempty zero-value bool) - ArgoCD kept flagging a
  # phantom diff on it regardless of whether git declared it explicitly.
  # Removing it from git didn't stop the flapping, so just tell ArgoCD to
  # stop comparing that field on any Application it manages.
  ignoreDifferences:
    - group: argoproj.io
      kind: Application
      jsonPointers:
        - /spec/source/directory/recurse
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
