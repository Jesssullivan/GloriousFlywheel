# GitLab Runner Module
#
# Deploys GitLab Runner to Kubernetes via Helm chart.
# Supports multiple runner types: docker, dind, rocky8, rocky9, nix.
# Includes HPA, monitoring, and cleanup configuration.

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

# =============================================================================
# Kubernetes Namespace
# =============================================================================

resource "kubernetes_namespace_v1" "runner" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

# =============================================================================
# GitLab Runner Helm Release
# =============================================================================

resource "helm_release" "gitlab_runner" {
  name             = var.runner_name
  repository       = "https://charts.gitlab.io"
  chart            = "gitlab-runner"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false

  depends_on = [kubernetes_namespace_v1.runner]

  # Runner token (sensitive)
  set_sensitive {
    name  = "runnerToken"
    value = var.runner_token
  }

  # GitLab configuration
  set {
    name  = "gitlabUrl"
    value = var.gitlab_url
  }

  # Concurrency
  set {
    name  = "concurrent"
    value = tostring(var.concurrent_jobs)
  }

  # RBAC
  set {
    name  = "rbac.create"
    value = tostring(var.rbac_create)
  }

  set {
    name  = "rbac.clusterWideAccess"
    value = tostring(var.cluster_wide_access || var.namespace_per_job)
  }

  # Runner configuration
  set {
    name  = "runners.privileged"
    value = tostring(local.privileged)
  }

  set {
    name  = "runners.tags"
    value = join("\\,", local.runner_tags)
  }

  set {
    name  = "runners.runUntagged"
    value = tostring(var.run_untagged)
  }

  set {
    name  = "runners.protected"
    value = tostring(var.protected)
  }

  # Manager pod resources (requests)
  set {
    name  = "resources.requests.cpu"
    value = var.cpu_request
  }

  set {
    name  = "resources.requests.memory"
    value = var.memory_request
  }

  # Manager pod resources (limits)
  set {
    name  = "resources.limits.cpu"
    value = var.cpu_limit
  }

  set {
    name  = "resources.limits.memory"
    value = var.memory_limit
  }

  # Manager pod priority class
  dynamic "set" {
    for_each = var.manager_priority_class_name != "" ? [var.manager_priority_class_name] : []
    content {
      name  = "priorityClassName"
      value = set.value
    }
  }

  # Metrics
  set {
    name  = "metrics.enabled"
    value = tostring(var.metrics_enabled)
  }

  # Pod labels
  dynamic "set" {
    for_each = var.pod_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  # Pod annotations
  dynamic "set" {
    for_each = var.pod_annotations
    content {
      name  = "podAnnotations.${set.key}"
      value = set.value
    }
  }

  # Node selector
  dynamic "set" {
    for_each = var.node_selector
    content {
      name  = "nodeSelector.${set.key}"
      value = set.value
    }
  }

  # Tolerations
  dynamic "set" {
    for_each = var.tolerations
    content {
      name  = "tolerations[${set.key}].key"
      value = set.value.key
    }
  }

  dynamic "set" {
    for_each = var.tolerations
    content {
      name  = "tolerations[${set.key}].operator"
      value = set.value.operator
    }
  }

  dynamic "set" {
    for_each = var.tolerations
    content {
      name  = "tolerations[${set.key}].effect"
      value = set.value.effect
    }
  }

  # Additional values including runner config
  values = concat(
    [
      yamlencode({
        runners = {
          config = local.runner_config_toml
        }
      })
    ],
    local.manager_affinity != null ? [yamlencode({
      podLabels = local.manager_spread_labels
      affinity  = local.manager_affinity
    })] : [],
    var.additional_values != "" ? [var.additional_values] : []
  )
}
