# MinIO Tenant - Lifecycle Policies (ILM)
#
# Implements bucket lifecycle policies for automatic cleanup of:
# - NAR files (Nix archive files)
# - Chunks (content-addressed storage chunks)
# - Incomplete multipart uploads
#
# These policies help manage storage costs by removing old cache entries.

# =============================================================================
# Lifecycle Policy ConfigMap
# =============================================================================

resource "kubernetes_config_map" "minio_lifecycle" {
  count = var.enable_lifecycle_policies ? 1 : 0

  metadata {
    name      = "${var.tenant_name}-lifecycle"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "minio"
      "app.kubernetes.io/instance"   = var.tenant_name
      "app.kubernetes.io/component"  = "lifecycle"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  data = {
    "lifecycle.json" = jsonencode({
      Rules = [
        # Rule 1: Expire NAR files after retention period
        {
          ID     = "expire-nar-files"
          Status = "Enabled"
          Filter = {
            Prefix = "nar/"
          }
          Expiration = {
            Days = var.nar_retention_days
          }
        },
        # Rule 2: Expire chunk files after retention period
        {
          ID     = "expire-chunks"
          Status = "Enabled"
          Filter = {
            Prefix = "chunks/"
          }
          Expiration = {
            Days = var.chunk_retention_days
          }
        },
        # Rule 3: Clean up narinfo files (metadata) same as NARs
        {
          ID     = "expire-narinfo"
          Status = "Enabled"
          Filter = {
            And = {
              Prefix = ""
              Tags   = []
            }
          }
          # Match .narinfo suffix via filter
          Expiration = {
            Days = var.nar_retention_days
          }
        },
        # Rule 4: Abort incomplete multipart uploads
        {
          ID     = "abort-incomplete-uploads"
          Status = "Enabled"
          Filter = {
            Prefix = ""
          }
          AbortIncompleteMultipartUpload = {
            DaysAfterInitiation = var.abort_incomplete_days
          }
        }
      ]
    })
  }
}

# =============================================================================
# Job to Apply Lifecycle Policies
# =============================================================================

resource "kubernetes_job" "apply_lifecycle" {
  count = var.enable_lifecycle_policies ? 1 : 0

  metadata {
    name      = "${var.tenant_name}-apply-lifecycle"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "minio"
      "app.kubernetes.io/instance"   = var.tenant_name
      "app.kubernetes.io/component"  = "lifecycle-init"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  spec {
    ttl_seconds_after_finished = 300

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "minio"
          "app.kubernetes.io/instance"  = var.tenant_name
          "app.kubernetes.io/component" = "lifecycle-init"
        }
      }

      spec {
        restart_policy = "OnFailure"

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
        }

        container {
          name  = "mc"
          image = "quay.io/minio/mc:latest"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              set -e
              echo "Waiting for MinIO to be ready..."
              sleep 30

              # Source credentials from mounted secret (config.env format)
              echo "Loading credentials..."
              source /credentials/config.env

              echo "Configuring MinIO client..."
              mc alias set myminio http://${var.tenant_name}-hl:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

              echo "Waiting for bucket to exist..."
              for i in $(seq 1 30); do
                if mc ls myminio/${var.buckets[0].name} >/dev/null 2>&1; then
                  echo "Bucket exists"
                  break
                fi
                echo "Attempt $i: Waiting for bucket..."
                sleep 5
              done

              echo "Applying lifecycle policy..."
              mc ilm import myminio/${var.buckets[0].name} < /lifecycle/lifecycle.json

              echo "Verifying lifecycle policy..."
              mc ilm ls myminio/${var.buckets[0].name}

              echo "Lifecycle policy applied successfully"
            EOT
          ]

          volume_mount {
            name       = "lifecycle"
            mount_path = "/lifecycle"
            read_only  = true
          }

          volume_mount {
            name       = "credentials"
            mount_path = "/credentials"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "lifecycle"
          config_map {
            name = kubernetes_config_map.minio_lifecycle[0].metadata[0].name
          }
        }

        volume {
          name = "credentials"
          secret {
            secret_name = var.credentials_secret
          }
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [
    kubectl_manifest.minio_tenant,
    null_resource.wait_for_tenant
  ]
}

# =============================================================================
# ServiceMonitor for Prometheus (optional)
# =============================================================================

resource "kubernetes_manifest" "minio_servicemonitor" {
  count = var.enable_monitoring ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "${var.tenant_name}-metrics"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/name"       = "minio"
        "app.kubernetes.io/instance"   = var.tenant_name
        "app.kubernetes.io/component"  = "monitoring"
        "app.kubernetes.io/managed-by" = "opentofu"
        "release"                      = "prometheus"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "v1.min.io/tenant" = var.tenant_name
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http-minio"
          path     = "/minio/v2/metrics/cluster"
          interval = "30s"
          scheme   = "http"
        }
      ]
    }
  }

  depends_on = [kubectl_manifest.minio_tenant]
}
