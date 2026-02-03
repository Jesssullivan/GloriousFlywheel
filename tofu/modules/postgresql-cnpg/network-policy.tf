# CloudNativePG PostgreSQL - Network Policies
#
# Strict network isolation for PostgreSQL cluster:
# - Only allow ingress from specified namespaces/pods
# - Allow egress for backups to S3
# - Allow inter-cluster replication

# =============================================================================
# Network Policy - PostgreSQL Cluster Ingress
# =============================================================================

resource "kubernetes_network_policy" "pg_ingress" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.name}-ingress"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    pod_selector {
      match_labels = {
        "cnpg.io/cluster" = var.name
      }
    }

    policy_types = ["Ingress"]

    # Allow PostgreSQL port from allowed namespaces
    dynamic "ingress" {
      for_each = length(var.allowed_namespaces) > 0 ? [1] : []
      content {
        from {
          dynamic "namespace_selector" {
            for_each = var.allowed_namespaces
            content {
              match_labels = {
                "kubernetes.io/metadata.name" = namespace_selector.value
              }
            }
          }
        }

        ports {
          protocol = "TCP"
          port     = 5432
        }
      }
    }

    # Allow from specific pods in same namespace (e.g., Attic pods)
    dynamic "ingress" {
      for_each = length(var.allowed_pod_labels) > 0 ? [1] : []
      content {
        from {
          pod_selector {
            match_labels = var.allowed_pod_labels
          }
        }

        ports {
          protocol = "TCP"
          port     = 5432
        }
      }
    }

    # Allow inter-cluster replication
    ingress {
      from {
        pod_selector {
          match_labels = {
            "cnpg.io/cluster" = var.name
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 5432
      }
    }

    # Allow CNPG operator access
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.cnpg_operator_namespace
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "cloudnative-pg"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 5432
      }
      ports {
        protocol = "TCP"
        port     = 8000 # Metrics port
      }
    }

    # Allow Prometheus scraping (if monitoring enabled)
    dynamic "ingress" {
      for_each = var.enable_monitoring && var.prometheus_namespace != "" ? [1] : []
      content {
        from {
          namespace_selector {
            match_labels = {
              "kubernetes.io/metadata.name" = var.prometheus_namespace
            }
          }
        }

        ports {
          protocol = "TCP"
          port     = 9187 # PostgreSQL exporter metrics
        }
      }
    }
  }
}

# =============================================================================
# Network Policy - PostgreSQL Cluster Egress
# =============================================================================

resource "kubernetes_network_policy" "pg_egress" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.name}-egress"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    pod_selector {
      match_labels = {
        "cnpg.io/cluster" = var.name
      }
    }

    policy_types = ["Egress"]

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {}
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = 53
      }
      ports {
        protocol = "TCP"
        port     = 53
      }
    }

    # Allow Kubernetes API access for CNPG instance manager
    # Required for leader election, status reporting, and cluster coordination
    egress {
      to {
        ip_block {
          cidr = var.kubernetes_api_cidr
        }
      }

      ports {
        protocol = "TCP"
        port     = 443
      }
    }

    # Allow inter-cluster replication
    egress {
      to {
        pod_selector {
          match_labels = {
            "cnpg.io/cluster" = var.name
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 5432
      }
    }

    # Allow backup to S3 endpoints
    dynamic "egress" {
      for_each = var.enable_backup ? [1] : []
      content {
        # Allow HTTPS to any (S3 endpoints)
        ports {
          protocol = "TCP"
          port     = 443
        }
      }
    }
  }
}

# =============================================================================
# Network Policy Variables
# =============================================================================

variable "enable_network_policy" {
  description = "Enable network policies for PostgreSQL cluster"
  type        = bool
  default     = true
}

variable "allowed_namespaces" {
  description = "List of namespaces allowed to connect to PostgreSQL"
  type        = list(string)
  default     = []
}

variable "allowed_pod_labels" {
  description = "Labels of pods in same namespace allowed to connect"
  type        = map(string)
  default     = {}
}

variable "cnpg_operator_namespace" {
  description = "Namespace where CNPG operator is installed"
  type        = string
  default     = "cnpg-system"
}

variable "prometheus_namespace" {
  description = "Namespace where Prometheus is installed (for metrics scraping)"
  type        = string
  default     = "monitoring"
}

variable "kubernetes_api_cidr" {
  description = "CIDR for Kubernetes API server (for CNPG instance manager communication)"
  type        = string
  default     = "10.43.0.1/32" # Default Civo K8s API service IP
}
