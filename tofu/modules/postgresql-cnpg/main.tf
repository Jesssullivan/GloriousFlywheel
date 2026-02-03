# CloudNativePG PostgreSQL Cluster Module
#
# Production-grade PostgreSQL cluster using CloudNativePG operator.
# Includes TLS encryption, network policies, backup to S3, and HA configuration.
#
# Usage:
#   module "attic_pg" {
#     source = "../../modules/postgresql-cnpg"
#
#     name            = "attic-pg"
#     namespace       = "nix-cache"
#     database_name   = "attic"
#     owner_name      = "attic"
#
#     # HA configuration
#     instances = 3
#
#     # Backup to S3
#     enable_backup           = true
#     backup_s3_endpoint      = "https://objectstore.nyc1.civo.com"
#     backup_s3_bucket        = "attic-pg-backup"
#     backup_s3_credentials_secret = "attic-s3-credentials"
#   }
#
# Security Features:
#   - TLS encryption for all connections (hostssl only)
#   - SCRAM-SHA-256 password authentication
#   - Network policies restricting access
#   - Audit logging enabled
#   - No superuser access for applications
#
# Prerequisites:
#   - CloudNativePG operator installed
#   - cert-manager for TLS certificates
#   - S3 credentials secret for backups

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/component"  = "database"
    "app.kubernetes.io/managed-by" = "opentofu"
    "app.kubernetes.io/part-of"    = var.part_of
    "cnpg.io/cluster"              = var.name
  }

  # Connection string format (without password - get from secret)
  # Password is stored in secret: ${var.name}-app
  connection_host = "${var.name}-rw.${var.namespace}.svc.cluster.local"
  connection_ro_host = "${var.name}-ro.${var.namespace}.svc.cluster.local"
}

# =============================================================================
# Random Password for Application User
# =============================================================================

resource "random_password" "app_password" {
  count = var.generate_password ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# =============================================================================
# Application Credentials Secret
# =============================================================================

resource "kubernetes_secret" "app_credentials" {
  metadata {
    name      = "${var.name}-app-credentials"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    username = var.owner_name
    password = var.generate_password ? random_password.app_password[0].result : var.app_password
  }

  type = "kubernetes.io/basic-auth"
}

# =============================================================================
# S3 Backup Credentials Secret (if not provided externally)
# =============================================================================

resource "kubernetes_secret" "s3_credentials" {
  count = var.enable_backup && var.create_s3_credentials_secret ? 1 : 0

  metadata {
    name      = "${var.name}-s3-credentials"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    ACCESS_KEY_ID     = var.backup_s3_access_key_id
    SECRET_ACCESS_KEY = var.backup_s3_secret_access_key
  }

  type = "Opaque"
}

# =============================================================================
# CloudNativePG Cluster
# =============================================================================

# Build the cluster spec as a local to use with yamlencode
locals {
  cluster_spec = {
    instances = var.instances

    # PostgreSQL configuration with security hardening
    postgresql = {
      parameters = merge(
        {
          # Connection limits
          max_connections = tostring(var.max_connections)

          # Memory settings
          shared_buffers = var.shared_buffers

          # Security settings
          password_encryption = "scram-sha-256"

          # Audit logging
          log_statement       = var.log_statement
          log_connections     = "on"
          log_disconnections  = "on"
          log_lock_waits      = "on"
          log_checkpoints     = "on"

          # Statement timeout (prevent long-running queries)
          statement_timeout = var.statement_timeout

          # Note: SSL is enforced via pg_hba rules, not via the ssl parameter
          # CNPG manages SSL internally and doesn't allow setting the ssl parameter
        },
        var.additional_postgresql_parameters
      )

      # pg_hba.conf - enforce SSL and SCRAM-SHA-256
      pg_hba = concat(
        [
          # Only allow SSL connections with SCRAM-SHA-256 authentication
          "hostssl all all all scram-sha-256"
        ],
        var.additional_pg_hba_rules
      )
    }

    # Bootstrap configuration
    bootstrap = {
      initdb = {
        database = var.database_name
        owner    = var.owner_name
        secret = {
          name = kubernetes_secret.app_credentials.metadata[0].name
        }
        # Locale settings
        localeCType   = var.locale
        localeCollate = var.locale
        # Encoding
        encoding = "UTF8"
      }
    }

    # Storage configuration
    storage = {
      size         = var.storage_size
      storageClass = var.storage_class
    }

    # Backup configuration
    backup = var.enable_backup ? {
      barmanObjectStore = {
        destinationPath = "s3://${var.backup_s3_bucket}/${var.name}/"
        endpointURL     = var.backup_s3_endpoint
        s3Credentials = {
          accessKeyId = {
            name = var.create_s3_credentials_secret ? kubernetes_secret.s3_credentials[0].metadata[0].name : var.backup_s3_credentials_secret
            key  = "ACCESS_KEY_ID"
          }
          secretAccessKey = {
            name = var.create_s3_credentials_secret ? kubernetes_secret.s3_credentials[0].metadata[0].name : var.backup_s3_credentials_secret
            key  = "SECRET_ACCESS_KEY"
          }
        }
        wal = {
          compression = var.backup_wal_compression
          maxParallel = var.backup_wal_max_parallel
        }
        data = {
          compression = var.backup_data_compression
        }
      }
      retentionPolicy = var.backup_retention_policy
    } : null

    # Resource limits
    resources = {
      requests = {
        memory = var.memory_request
        cpu    = var.cpu_request
      }
      limits = {
        memory = var.memory_limit
        cpu    = var.cpu_limit
      }
    }

    # Affinity for HA - spread across nodes
    affinity = {
      podAntiAffinityType = var.pod_anti_affinity_type
      topologyKey         = var.topology_key
    }

    # Monitoring
    monitoring = var.enable_monitoring ? {
      enablePodMonitor = true
      customQueriesConfigMap = var.custom_queries_configmap != "" ? [
        {
          name = var.custom_queries_configmap
          key  = "queries"
        }
      ] : []
    } : null

    # Logging configuration
    logLevel = var.log_level

    # Primary update strategy
    primaryUpdateStrategy = var.primary_update_strategy

    # Switchover delay for graceful failover
    switchoverDelay = var.switchover_delay

    # Start delay
    startDelay = var.start_delay

    # Stop delay
    stopDelay = var.stop_delay

    # Certificates - use cluster default or cert-manager
    certificates = var.enable_tls ? {
      serverTLSSecret      = var.server_tls_secret != "" ? var.server_tls_secret : null
      serverCASecret       = var.server_ca_secret != "" ? var.server_ca_secret : null
      clientCASecret       = var.client_ca_secret != "" ? var.client_ca_secret : null
      replicationTLSSecret = var.replication_tls_secret != "" ? var.replication_tls_secret : null
    } : null
  }
}

# Use kubectl_manifest instead of kubernetes_manifest to handle CNPG's
# server-side field defaulting which causes perpetual diffs
resource "kubectl_manifest" "cluster" {
  yaml_body = yamlencode({
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = local.cluster_spec
  })

  # Ignore fields that CNPG adds server-side defaults to
  # This prevents perpetual diffs from the operator adding default values
  ignore_fields = [
    "spec.postgresql.parameters",
    "spec.monitoring.customQueriesConfigMap"
  ]

  depends_on = [
    kubernetes_secret.app_credentials,
    kubernetes_secret.s3_credentials
  ]
}

# =============================================================================
# Scheduled Backup
# =============================================================================

resource "kubectl_manifest" "scheduled_backup" {
  count = var.enable_backup && var.enable_scheduled_backup ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "ScheduledBackup"
    metadata = {
      name      = "${var.name}-scheduled"
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      schedule = var.backup_schedule
      backupOwnerReference = "cluster"
      cluster = {
        name = var.name
      }
      immediate = var.backup_immediate
    }
  })

  depends_on = [kubectl_manifest.cluster]
}

# =============================================================================
# Pod Disruption Budget
# =============================================================================

resource "kubernetes_pod_disruption_budget_v1" "pg_pdb" {
  count = var.enable_pdb && var.instances > 1 ? 1 : 0

  metadata {
    name      = "${var.name}-pdb"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_available = var.pdb_min_available

    selector {
      match_labels = {
        "cnpg.io/cluster" = var.name
      }
    }
  }

  depends_on = [kubectl_manifest.cluster]
}
