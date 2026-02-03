# CloudNativePG Operator Module
#
# Installs the CloudNativePG operator via Helm for managing PostgreSQL clusters
# on Kubernetes. This is a cluster-wide operator that should be deployed once.
#
# Usage:
#   module "cnpg_operator" {
#     source = "../../modules/cnpg-operator"
#
#     namespace = "cnpg-system"
#   }
#
# Prerequisites:
#   - Kubernetes cluster with Helm provider configured
#   - cert-manager installed (optional but recommended for TLS)
#
# CloudNativePG Features:
#   - Automated failover and self-healing
#   - Continuous backup to S3-compatible storage
#   - Point-in-time recovery (PITR)
#   - Rolling updates with zero downtime
#   - Prometheus metrics integration

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# =============================================================================
# Namespace
# =============================================================================

resource "kubernetes_namespace" "cnpg_system" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "cloudnative-pg"
      "app.kubernetes.io/component"  = "operator"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# =============================================================================
# CloudNativePG Operator Helm Release
# =============================================================================

resource "helm_release" "cnpg" {
  name       = "cnpg"
  namespace  = var.create_namespace ? kubernetes_namespace.cnpg_system[0].metadata[0].name : var.namespace
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = var.chart_version

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  timeout          = var.helm_timeout

  # Operator configuration
  values = [
    yamlencode({
      # Replicas for HA operator
      replicaCount = var.operator_replicas

      # Resource limits for operator
      resources = {
        requests = {
          cpu    = var.operator_cpu_request
          memory = var.operator_memory_request
        }
        limits = {
          cpu    = var.operator_cpu_limit
          memory = var.operator_memory_limit
        }
      }

      # Monitoring
      monitoring = {
        podMonitorEnabled          = var.enable_pod_monitor
        grafanaDashboard = {
          create = var.enable_grafana_dashboard
        }
      }

      # Security context
      securityContext = {
        runAsNonRoot = true
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      # Pod security context
      podSecurityContext = {
        runAsNonRoot = true
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      # Webhook configuration
      webhook = {
        mutating = {
          failurePolicy = var.webhook_failure_policy
        }
        validating = {
          failurePolicy = var.webhook_failure_policy
        }
      }

      # Leader election
      config = {
        # Enable leader election for HA
        ENABLE_INSTANCE_MANAGER_INPLACE_UPDATES = var.enable_inplace_updates
      }
    })
  ]

  dynamic "set" {
    for_each = var.additional_helm_values
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [kubernetes_namespace.cnpg_system]
}

# =============================================================================
# Outputs
# =============================================================================

output "namespace" {
  description = "Namespace where CloudNativePG operator is installed"
  value       = var.create_namespace ? kubernetes_namespace.cnpg_system[0].metadata[0].name : var.namespace
}

output "chart_version" {
  description = "Installed CloudNativePG chart version"
  value       = helm_release.cnpg.version
}

output "operator_ready" {
  description = "Indicates operator is deployed"
  value       = helm_release.cnpg.status == "deployed"
}

# =============================================================================
# Variables
# =============================================================================

variable "namespace" {
  description = "Namespace for CloudNativePG operator"
  type        = string
  default     = "cnpg-system"
}

variable "create_namespace" {
  description = "Create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "CloudNativePG Helm chart version"
  type        = string
  default     = "0.20.0"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations (seconds)"
  type        = number
  default     = 600
}

variable "operator_replicas" {
  description = "Number of operator replicas for HA"
  type        = number
  default     = 1
}

variable "operator_cpu_request" {
  description = "CPU request for operator"
  type        = string
  default     = "100m"
}

variable "operator_cpu_limit" {
  description = "CPU limit for operator"
  type        = string
  default     = "500m"
}

variable "operator_memory_request" {
  description = "Memory request for operator"
  type        = string
  default     = "128Mi"
}

variable "operator_memory_limit" {
  description = "Memory limit for operator"
  type        = string
  default     = "256Mi"
}

variable "enable_pod_monitor" {
  description = "Enable Prometheus PodMonitor for operator metrics"
  type        = bool
  default     = true
}

variable "enable_grafana_dashboard" {
  description = "Create Grafana dashboard ConfigMap"
  type        = bool
  default     = false
}

variable "webhook_failure_policy" {
  description = "Webhook failure policy (Fail or Ignore)"
  type        = string
  default     = "Fail"

  validation {
    condition     = contains(["Fail", "Ignore"], var.webhook_failure_policy)
    error_message = "webhook_failure_policy must be 'Fail' or 'Ignore'"
  }
}

variable "enable_inplace_updates" {
  description = "Enable in-place updates for instance manager"
  type        = string
  default     = "true"
}

variable "additional_helm_values" {
  description = "Additional Helm values to set"
  type        = map(string)
  default     = {}
}
