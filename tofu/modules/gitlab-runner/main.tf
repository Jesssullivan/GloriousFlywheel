# GitLab Runner Module
#
# Deploys GitLab Runner to Kubernetes via Helm chart.
# Supports runner token authentication for GitLab 16+.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Kubernetes namespace
resource "kubernetes_namespace_v1" "runner" {
  count = var.create_namespace ? 1 : 0
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "gitlab-runner"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# GitLab Runner Helm release
resource "helm_release" "gitlab_runner" {
  name             = var.runner_name
  repository       = "https://charts.gitlab.io"
  chart            = "gitlab-runner"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false

  depends_on = [kubernetes_namespace_v1.runner]

  set_sensitive {
    name  = "runnerToken"
    value = var.runner_token
  }

  set {
    name  = "gitlabUrl"
    value = var.gitlab_url
  }

  set {
    name  = "concurrent"
    value = tostring(var.concurrent_jobs)
  }

  set {
    name  = "rbac.create"
    value = tostring(var.rbac_create)
  }

  set {
    name  = "rbac.clusterWideAccess"
    value = tostring(var.cluster_wide_access)
  }

  set {
    name  = "runners.privileged"
    value = tostring(var.privileged)
  }

  set {
    name  = "runners.tags"
    value = join("\\,", var.runner_tags)
  }

  set {
    name  = "resources.requests.cpu"
    value = var.cpu_request
  }

  set {
    name  = "resources.requests.memory"
    value = var.memory_request
  }

  values = var.additional_values != "" ? [var.additional_values] : []
}
