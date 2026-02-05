# bazel-cache Module
#
# Deploys bazel-remote cache server with S3/MinIO backend.
# Optimized for Kubernetes environments with HPA and monitoring.
#
# Usage:
#   module "bazel_cache" {
#     source = "../../modules/bazel-cache"
#
#     name      = "bazel-cache"
#     namespace = "attic-cache"
#
#     # MinIO backend (existing in namespace)
#     s3_endpoint   = "minio.attic-cache.svc.cluster.local:9000"
#     s3_bucket     = "bazel-cache"
#     s3_secret     = "bazel-cache-s3-credentials"
#
#     # Scaling
#     min_replicas = 2
#     max_replicas = 4
#   }

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  labels = merge(
    {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/instance"   = "${var.name}-${var.namespace}"
      "app.kubernetes.io/component"  = "build-cache"
      "app.kubernetes.io/part-of"    = "build-infrastructure"
      "app.kubernetes.io/managed-by" = "opentofu"
    },
    var.additional_labels
  )

  selector_labels = {
    "app.kubernetes.io/name"     = var.name
    "app.kubernetes.io/instance" = "${var.name}-${var.namespace}"
  }

  # Service endpoints
  grpc_port = 9092
  http_port = 8080

  # Strip scheme from S3 endpoint (bazel-remote expects host:port, not full URL)
  # Removes http:// or https:// prefix
  s3_endpoint_host = replace(replace(var.s3_endpoint, "https://", ""), "http://", "")
}

# =============================================================================
# ConfigMap for bazel-remote configuration
# =============================================================================

resource "kubernetes_config_map_v1" "config" {
  metadata {
    name      = "${var.name}-config"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    # S3 config is handled entirely via environment variables to avoid
    # config file/CLI conflicts. Only non-S3 settings go in this file.
    "config.yaml" = yamlencode({
      # Required storage configuration
      dir      = "/data"
      max_size = var.max_cache_size_gb

      # Server settings
      host      = "0.0.0.0"
      port      = local.http_port
      grpc_port = local.grpc_port

      # Performance tuning
      num_uploaders      = var.num_uploaders
      max_queued_uploads = var.max_queued_uploads

      # Metrics
      enable_endpoint_metrics = var.enable_metrics

      # Access logging
      access_log_level = var.access_log_level
    })
  }
}

# =============================================================================
# Deployment
# =============================================================================

resource "kubernetes_deployment_v1" "main" {
  wait_for_rollout = var.wait_for_rollout

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels

    annotations = {
      "app.kubernetes.io/created-by" = "opentofu"
    }
  }

  spec {
    replicas = var.min_replicas

    selector {
      match_labels = local.selector_labels
    }

    template {
      metadata {
        labels = local.labels

        annotations = {
          "prometheus.io/scrape" = tostring(var.enable_metrics)
          "prometheus.io/port"   = tostring(local.http_port)
          "prometheus.io/path"   = "/metrics"
          # Force pod restart when config changes
          "checksum/config" = sha256(kubernetes_config_map_v1.config.data["config.yaml"])
        }
      }

      spec {
        service_account_name = var.service_account_name

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
        }

        # Init containers for waiting on dependencies
        dynamic "init_container" {
          for_each = var.init_containers
          content {
            name    = init_container.value.name
            image   = init_container.value.image
            command = init_container.value.command
            args    = init_container.value.args
          }
        }

        container {
          name  = "bazel-remote"
          image = var.image

          # S3 config is handled via environment variables (not config file)
          # to avoid conflicts between config file and CLI args
          args = ["--config_file=/etc/bazel-remote/config.yaml"]

          port {
            container_port = local.grpc_port
            name           = "grpc"
            protocol       = "TCP"
          }

          port {
            container_port = local.http_port
            name           = "http"
            protocol       = "TCP"
          }

          # S3 configuration via environment variables
          env {
            name  = "BAZEL_REMOTE_S3_ENDPOINT"
            value = local.s3_endpoint_host
          }

          env {
            name  = "BAZEL_REMOTE_S3_BUCKET"
            value = var.s3_bucket
          }

          env {
            name  = "BAZEL_REMOTE_S3_PREFIX"
            value = var.s3_prefix
          }

          env {
            name  = "BAZEL_REMOTE_S3_AUTH_METHOD"
            value = "access_key"
          }

          env {
            name  = "BAZEL_REMOTE_S3_DISABLE_SSL"
            value = tostring(var.s3_disable_ssl)
          }

          # S3 credentials from secret
          env {
            name = "BAZEL_REMOTE_S3_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = var.s3_secret
                key  = "access-key"
              }
            }
          }

          env {
            name = "BAZEL_REMOTE_S3_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = var.s3_secret
                key  = "secret-key"
              }
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/bazel-remote"
            read_only  = true
          }

          volume_mount {
            name       = "cache"
            mount_path = "/data"
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          # Liveness probe using gRPC health check
          liveness_probe {
            grpc {
              port = local.grpc_port
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          # Readiness probe
          readiness_probe {
            http_get {
              path = "/status"
              port = local.http_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.config.metadata[0].name
          }
        }

        volume {
          name = "cache"
          empty_dir {
            size_limit = "${var.local_cache_size_gb}Gi"
          }
        }

        # Topology spread for HA
        topology_spread_constraint {
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

  lifecycle {
    ignore_changes = [
      spec[0].replicas, # Managed by HPA
    ]
  }
}

# =============================================================================
# Service
# =============================================================================

resource "kubernetes_service_v1" "main" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    selector = local.selector_labels

    port {
      port        = local.grpc_port
      target_port = local.grpc_port
      name        = "grpc"
      protocol    = "TCP"
    }

    port {
      port        = local.http_port
      target_port = local.http_port
      name        = "http"
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# =============================================================================
# Ingress (optional, for external access)
# =============================================================================

resource "kubernetes_ingress_v1" "main" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels

    annotations = merge(
      {
        "kubernetes.io/ingress.class"                    = var.ingress_class
        "cert-manager.io/cluster-issuer"                 = var.cert_manager_issuer
        "nginx.ingress.kubernetes.io/backend-protocol"   = "GRPC"
        "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
        "nginx.ingress.kubernetes.io/proxy-read-timeout" = "600"
      },
      var.ingress_annotations
    )
  }

  spec {
    ingress_class_name = var.ingress_class

    tls {
      hosts       = [var.ingress_host]
      secret_name = "${var.name}-tls"
    }

    rule {
      host = var.ingress_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.main.metadata[0].name
              port {
                number = local.grpc_port
              }
            }
          }
        }
      }
    }
  }
}
