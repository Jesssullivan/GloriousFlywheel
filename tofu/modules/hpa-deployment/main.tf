# HPA-Enabled Deployment Module
#
# Generic Horizontal Pod Autoscaler-enabled deployment module for Civo Kubernetes.
# Designed for stateless services that need object storage backends.
#
# Usage:
#   module "attic" {
#     source = "../../modules/hpa-deployment"
#
#     name           = "attic"
#     namespace      = "nix-cache"
#     image          = "heywoodlh/attic:latest"
#     container_port = 8080
#
#     env_from_secrets = ["attic-secrets"]
#     config_map_mounts = [{
#       name       = "config"
#       mount_path = "/etc/attic"
#       config_map = "attic-config"
#     }]
#
#     # HPA configuration
#     min_replicas        = 2
#     max_replicas        = 10
#     cpu_target_percent  = 70
#     memory_target_percent = 80
#   }
#
# Reusable for:
#   - Attic (Nix binary cache)
#   - Quay (container registry)
#   - Pulp (artifact repository)
#   - Rocky DNF mirrors

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# =============================================================================
# Computed Values
# =============================================================================

locals {
  labels = merge(
    {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/instance"   = "${var.name}-${var.namespace}"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/component"  = var.component
    },
    var.additional_labels
  )

  selector_labels = {
    "app.kubernetes.io/name"     = var.name
    "app.kubernetes.io/instance" = "${var.name}-${var.namespace}"
  }

  # Merge resource requests and limits
  resource_requests = {
    memory = var.memory_request
    cpu    = var.cpu_request
  }

  resource_limits = {
    memory = var.memory_limit
    cpu    = var.cpu_limit
  }
}

# =============================================================================
# Deployment
# =============================================================================

resource "kubernetes_deployment" "main" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels

    annotations = merge(
      {
        "app.kubernetes.io/created-by" = "opentofu"
      },
      var.additional_annotations
    )
  }

  spec {
    replicas = var.min_replicas

    selector {
      match_labels = local.selector_labels
    }

    template {
      metadata {
        labels = local.labels

        annotations = merge(
          {
            "prometheus.io/scrape" = tostring(var.enable_prometheus_scrape)
            "prometheus.io/port"   = tostring(var.metrics_port)
            "prometheus.io/path"   = var.metrics_path
          },
          var.pod_annotations
        )
      }

      spec {
        service_account_name = var.service_account_name

        dynamic "security_context" {
          for_each = var.enable_security_context ? [1] : []
          content {
            run_as_non_root = true
            run_as_user     = var.run_as_user
            run_as_group    = var.run_as_group
            fs_group        = var.fs_group
          }
        }

        container {
          name  = var.name
          image = var.image

          args = var.container_args

          dynamic "port" {
            for_each = [var.container_port]
            content {
              container_port = port.value
              name           = "http"
              protocol       = "TCP"
            }
          }

          dynamic "port" {
            for_each = var.enable_prometheus_scrape && var.metrics_port != var.container_port ? [var.metrics_port] : []
            content {
              container_port = port.value
              name           = "metrics"
              protocol       = "TCP"
            }
          }

          # Environment from secrets
          dynamic "env_from" {
            for_each = var.env_from_secrets
            content {
              secret_ref {
                name = env_from.value
              }
            }
          }

          # Environment from config maps
          dynamic "env_from" {
            for_each = var.env_from_config_maps
            content {
              config_map_ref {
                name = env_from.value
              }
            }
          }

          # Direct environment variables
          dynamic "env" {
            for_each = var.environment_variables
            content {
              name  = env.key
              value = env.value
            }
          }

          # Volume mounts for config maps
          dynamic "volume_mount" {
            for_each = var.config_map_mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              read_only  = lookup(volume_mount.value, "read_only", true)
            }
          }

          # Volume mounts for secrets
          dynamic "volume_mount" {
            for_each = var.secret_mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              read_only  = lookup(volume_mount.value, "read_only", true)
            }
          }

          resources {
            requests = local.resource_requests
            limits   = local.resource_limits
          }

          # Liveness probe
          dynamic "liveness_probe" {
            for_each = var.enable_liveness_probe ? [1] : []
            content {
              http_get {
                path = var.health_check_path
                port = var.container_port
              }
              initial_delay_seconds = var.liveness_initial_delay
              period_seconds        = var.liveness_period
              timeout_seconds       = var.liveness_timeout
              failure_threshold     = var.liveness_failure_threshold
            }
          }

          # Readiness probe
          dynamic "readiness_probe" {
            for_each = var.enable_readiness_probe ? [1] : []
            content {
              http_get {
                path = var.health_check_path
                port = var.container_port
              }
              initial_delay_seconds = var.readiness_initial_delay
              period_seconds        = var.readiness_period
              timeout_seconds       = var.readiness_timeout
              failure_threshold     = var.readiness_failure_threshold
            }
          }
        }

        # Volumes from config maps
        dynamic "volume" {
          for_each = var.config_map_mounts
          content {
            name = volume.value.name
            config_map {
              name = volume.value.config_map
            }
          }
        }

        # Volumes from secrets
        dynamic "volume" {
          for_each = var.secret_mounts
          content {
            name = volume.value.name
            secret {
              secret_name = volume.value.secret
            }
          }
        }

        # Node selector
        node_selector = length(var.node_selector) > 0 ? var.node_selector : null

        # Tolerations
        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = lookup(toleration.value, "operator", "Equal")
            value    = lookup(toleration.value, "value", "")
            effect   = toleration.value.effect
          }
        }

        # Topology spread constraints for HA
        dynamic "topology_spread_constraint" {
          for_each = var.enable_topology_spread ? [1] : []
          content {
            max_skew           = 1
            topology_key       = "topology.kubernetes.io/zone"
            when_unsatisfiable = "ScheduleAnyway"
            label_selector {
              match_labels = local.selector_labels
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].replicas, # Managed by HPA
    ]
  }
}

# =============================================================================
# Service
# =============================================================================

resource "kubernetes_service" "main" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels

    annotations = var.service_annotations
  }

  spec {
    selector = local.selector_labels

    port {
      port        = var.service_port
      target_port = var.container_port
      name        = "http"
      protocol    = "TCP"
    }

    dynamic "port" {
      for_each = var.enable_prometheus_scrape && var.metrics_port != var.container_port ? [1] : []
      content {
        port        = var.metrics_port
        target_port = var.metrics_port
        name        = "metrics"
        protocol    = "TCP"
      }
    }

    type = var.service_type
  }
}

# =============================================================================
# Ingress
# =============================================================================

resource "kubernetes_ingress_v1" "main" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels

    annotations = merge(
      {
        "kubernetes.io/ingress.class"             = var.ingress_class
        "cert-manager.io/cluster-issuer"          = var.cert_manager_issuer
        "nginx.ingress.kubernetes.io/proxy-body-size" = var.ingress_proxy_body_size
      },
      var.ingress_annotations
    )
  }

  spec {
    ingress_class_name = var.ingress_class

    dynamic "tls" {
      for_each = var.enable_tls ? [1] : []
      content {
        hosts       = [var.ingress_host]
        secret_name = "${var.name}-tls"
      }
    }

    rule {
      host = var.ingress_host

      http {
        path {
          path      = var.ingress_path
          path_type = var.ingress_path_type

          backend {
            service {
              name = kubernetes_service.main.metadata[0].name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }
  }
}

# =============================================================================
# Horizontal Pod Autoscaler
# =============================================================================

resource "kubernetes_horizontal_pod_autoscaler_v2" "main" {
  count = var.enable_hpa ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.main.metadata[0].name
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # CPU-based scaling
    dynamic "metric" {
      for_each = var.cpu_target_percent > 0 ? [1] : []
      content {
        type = "Resource"
        resource {
          name = "cpu"
          target {
            type                = "Utilization"
            average_utilization = var.cpu_target_percent
          }
        }
      }
    }

    # Memory-based scaling
    dynamic "metric" {
      for_each = var.memory_target_percent > 0 ? [1] : []
      content {
        type = "Resource"
        resource {
          name = "memory"
          target {
            type                = "Utilization"
            average_utilization = var.memory_target_percent
          }
        }
      }
    }

    # Custom metrics (e.g., requests per second)
    dynamic "metric" {
      for_each = var.custom_metrics
      content {
        type = "Pods"
        pods {
          metric {
            name = metric.value.name
          }
          target {
            type          = "AverageValue"
            average_value = metric.value.target_value
          }
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = var.scale_down_stabilization_seconds
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = var.scale_down_percent
          period_seconds = 60
        }
        policy {
          type           = "Pods"
          value          = var.scale_down_pods
          period_seconds = 60
        }
      }

      scale_up {
        stabilization_window_seconds = var.scale_up_stabilization_seconds
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = var.scale_up_percent
          period_seconds = 15
        }
        policy {
          type           = "Pods"
          value          = var.scale_up_pods
          period_seconds = 15
        }
      }
    }
  }
}

# =============================================================================
# Pod Disruption Budget
# =============================================================================

resource "kubernetes_pod_disruption_budget_v1" "main" {
  count = var.enable_pdb ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_available = var.pdb_min_available

    selector {
      match_labels = local.selector_labels
    }
  }
}
