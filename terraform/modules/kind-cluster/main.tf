terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Defaults to 127.0.0.1, i.e. only reachable from the machine running
    # Docker. Set api_server_address to your LAN IP (e.g. 192.168.1.50) to
    # drive this cluster from another device on the same network - see
    # docs/SETUP.md "Remote access over LAN".
    networking {
      api_server_address = var.api_server_address
      api_server_port     = 6443
    }

    node {
      role = "control-plane"

      # Expose 80/443 on the host so ArgoCD/ingress can be reached without
      # extra port-forwarding.
      extra_port_mappings {
        container_port = 80
        host_port       = 8080
      }
      extra_port_mappings {
        container_port = 443
        host_port       = 8443
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Keep it light for a laptop-class cluster.
  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      controller = {
        resources = { requests = { cpu = "100m", memory = "256Mi" } }
      }
      server = {
        resources = { requests = { cpu = "50m", memory = "128Mi" } }
      }
      repoServer = {
        resources = { requests = { cpu = "50m", memory = "128Mi" } }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Root Application (app-of-apps). Everything else - the shorturl helm
# release, the otel-sidecar-injector controller, the collector gateway - is
# declared as child Applications under argocd/apps and reconciled from here.
resource "kubectl_manifest" "root_app" {
  yaml_body = templatefile("${path.module}/templates/root-app.yaml.tpl", {
    repo_url        = var.gitops_repo_url
    target_revision = var.target_revision
  })

  depends_on = [helm_release.argocd]
}
