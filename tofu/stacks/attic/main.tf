# Attic Stack - Nix Binary Cache Deployment
#
# Deploys Attic (self-hosted Nix binary cache) to Bates Kubernetes clusters
# (beehive for dev/review, rigel for staging/production).
#
# Architecture:
#   - Attic API Server: Stateless, HPA-enabled
#   - Attic GC Worker: Single replica for garbage collection
#   - PostgreSQL: CloudNativePG cluster
#   - S3 Storage: Object storage (NAR/chunk storage)
#   - Auth: Disabled (public read/write on internal network)
#
# Usage:
#   cd tofu/stacks/attic
#   tofu init
#   tofu plan -var-file=beehive.tfvars  # or rigel.tfvars
#   tofu apply -var-file=beehive.tfvars

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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    # civo provider disabled - using GitLab Kubernetes Agent
    # civo = {
    #   source  = "civo/civo"
    #   version = "~> 1.0"
    # }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# Kubernetes Provider Configuration (GitLab Kubernetes Agent)
# =============================================================================

provider "kubernetes" {
  # GitLab Kubernetes Agent authentication
  # When k8s_config_path is empty (default), uses KUBECONFIG env var set by GitLab CI
  # When specified, uses the explicit path (for local development)
  config_path    = var.k8s_config_path != "" ? var.k8s_config_path : null
  config_context = var.cluster_context
}

provider "helm" {
  kubernetes {
    config_path    = var.k8s_config_path != "" ? var.k8s_config_path : null
    config_context = var.cluster_context
  }
}

# Civo provider disabled - using GitLab Kubernetes Agent for Bates clusters
# provider "civo" {
#   token  = var.civo_api_key
#   region = var.civo_region
# }

provider "kubectl" {
  config_path      = var.k8s_config_path != "" ? var.k8s_config_path : null
  config_context   = var.cluster_context
  load_config_file = true
}

# =============================================================================
# Namespace
# =============================================================================

# Data source to look up existing namespace (for adopt mode)
data "kubernetes_namespace" "existing" {
  count = var.adopt_existing_namespace ? 1 : 0
  metadata {
    name = var.namespace
  }
}

# Create namespace only if not adopting existing one
resource "kubernetes_namespace" "nix_cache" {
  count = var.adopt_existing_namespace ? 0 : 1

  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "attic"
      "app.kubernetes.io/component"  = "nix-cache"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/part-of"    = "tinyland-infra"
      # Label for network policy namespace selection
      "kubernetes.io/metadata.name" = var.namespace
      # Pod Security Standards (PSS) - enforce baseline, warn on restricted
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }

    annotations = {
      "description" = "Nix binary cache powered by Attic"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["kubectl.kubernetes.io/last-applied-configuration"],
    ]
  }
}

# Local to get namespace name regardless of adopt mode
locals {
  namespace_name = var.adopt_existing_namespace ? data.kubernetes_namespace.existing[0].metadata[0].name : kubernetes_namespace.nix_cache[0].metadata[0].name
}

# =============================================================================
# Input Validation
# =============================================================================

# Validate database_url is not a placeholder when CNPG is disabled
check "database_url_required" {
  assert {
    condition     = var.use_cnpg_postgres || !can(regex("placeholder", var.database_url))
    error_message = "database_url cannot contain 'placeholder' when use_cnpg_postgres is false. Provide a real PostgreSQL connection string."
  }
}

# Validate S3 config is provided when MinIO is disabled
check "s3_config_required" {
  assert {
    condition = var.use_minio || (
      var.s3_endpoint != "" &&
      var.s3_bucket_name != "" &&
      var.s3_access_key_id != "" &&
      var.s3_secret_access_key != ""
    )
    error_message = "S3 configuration (s3_endpoint, s3_bucket_name, s3_access_key_id, s3_secret_access_key) is required when use_minio is false."
  }
}

# =============================================================================
# CloudNativePG Operator (Cluster-Wide)
# =============================================================================

module "cnpg_operator" {
  count  = var.use_cnpg_postgres && var.install_cnpg_operator ? 1 : 0
  source = "../../modules/cnpg-operator"

  namespace        = var.cnpg_operator_namespace
  create_namespace = var.cnpg_operator_create_namespace
  chart_version    = var.cnpg_chart_version

  operator_replicas       = 1
  operator_cpu_request    = "100m"
  operator_memory_request = "128Mi"

  enable_pod_monitor       = var.enable_prometheus_monitoring
  enable_grafana_dashboard = false
}

# =============================================================================
# MinIO Operator (Cluster-Wide - Optional)
# =============================================================================
# MinIO provides self-managed S3-compatible storage optimized for Nix binary
# cache workloads. When enabled, Attic uses MinIO instead of external S3.

module "minio_operator" {
  count  = var.use_minio && var.install_minio_operator ? 1 : 0
  source = "../../modules/minio-operator"

  namespace        = var.minio_operator_namespace
  create_namespace = var.minio_operator_create_namespace
  operator_version = var.minio_operator_version

  operator_replicas       = 1
  operator_cpu_request    = "50m"
  operator_memory_request = "64Mi"

  enable_console = false
}

# =============================================================================
# JWT Secret for Attic (HS256)
# =============================================================================

# Generate random JWT secret for internal signing (required even in auth-free mode)
resource "random_password" "attic_jwt_secret" {
  length  = 64
  special = false
}

# Base64 encode the JWT secret for Attic configuration
locals {
  attic_jwt_hs256_secret_base64 = base64encode(random_password.attic_jwt_secret.result)
}

# Store JWT signing key as a K8s Secret for init-cache Job and CI token generation
resource "kubernetes_secret" "attic_jwt_signing" {
  metadata {
    name      = "attic-jwt-signing"
    namespace = local.namespace_name

    labels = {
      "app.kubernetes.io/name"       = "attic"
      "app.kubernetes.io/component"  = "jwt-signing"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  data = {
    "hs256-secret-base64" = local.attic_jwt_hs256_secret_base64
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.nix_cache
  ]
}

# =============================================================================
# MinIO Credentials Secret
# =============================================================================

# Generate random password if not provided
resource "random_password" "minio_password" {
  count   = var.use_minio && var.minio_root_password == "" ? 1 : 0
  length  = 32
  special = false
}

locals {
  minio_root_password = var.use_minio ? (
    var.minio_root_password != "" ? var.minio_root_password : random_password.minio_password[0].result
  ) : ""
}

# MinIO credentials secret (required for tenant)
resource "kubernetes_secret" "minio_credentials" {
  count = var.use_minio ? 1 : 0

  metadata {
    name      = "minio-credentials"
    namespace = local.namespace_name

    labels = {
      "app.kubernetes.io/name"       = "minio"
      "app.kubernetes.io/component"  = "credentials"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  # MinIO operator expects credentials in config.env format
  data = {
    "config.env" = <<-EOT
      export MINIO_ROOT_USER="${var.minio_root_user}"
      export MINIO_ROOT_PASSWORD="${local.minio_root_password}"
    EOT
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.nix_cache
  ]
}

# =============================================================================
# MinIO Tenant (Per-Namespace)
# =============================================================================

module "minio_tenant" {
  count  = var.use_minio ? 1 : 0
  source = "../../modules/minio-tenant"

  tenant_name        = "attic-minio"
  namespace          = local.namespace_name
  distributed_mode   = var.minio_distributed_mode
  storage_class      = var.minio_storage_class != "" ? var.minio_storage_class : var.pg_storage_class
  volume_size        = var.minio_volume_size
  credentials_secret = kubernetes_secret.minio_credentials[0].metadata[0].name

  # Bucket configuration - includes pg-backup and bazel-cache buckets when enabled
  buckets = concat(
    [
      {
        name = var.minio_bucket_name
      }
    ],
    var.pg_enable_backup ? [
      {
        name = "pg-backup"
      }
    ] : [],
    var.enable_bazel_cache ? [
      {
        name = var.bazel_cache_bucket
      }
    ] : []
  )

  # Resource sizing
  cpu_request    = var.minio_cpu_request
  memory_request = var.minio_memory_request
  cpu_limit      = var.minio_cpu_limit
  memory_limit   = var.minio_memory_limit

  # Lifecycle policies
  enable_lifecycle_policies = true
  nar_retention_days        = var.minio_nar_retention_days
  chunk_retention_days      = var.minio_chunk_retention_days

  # Monitoring
  enable_monitoring = var.enable_prometheus_monitoring

  depends_on = [
    module.minio_operator,
    kubernetes_secret.minio_credentials
  ]
}

# =============================================================================
# S3 Configuration (MinIO or External)
# =============================================================================

# Validation: Ensure external S3 config is provided when MinIO is disabled
locals {
  # Validate external S3 config when MinIO is disabled
  _validate_s3 = var.use_minio ? true : (
    var.s3_endpoint != "" && var.s3_bucket_name != ""
  )

  # Validate S3 configuration when not using MinIO (includes credentials check)
  _s3_config_valid = var.use_minio ? true : (
    var.s3_endpoint != "" &&
    var.s3_bucket_name != "" &&
    var.s3_access_key_id != "" &&
    var.s3_secret_access_key != ""
  )

  # Use MinIO endpoint if enabled, otherwise use external S3
  effective_s3_endpoint = var.use_minio ? module.minio_tenant[0].s3_endpoint : var.s3_endpoint
  effective_s3_bucket   = var.use_minio ? var.minio_bucket_name : var.s3_bucket_name

  # S3 credentials for Attic
  effective_s3_access_key = var.use_minio ? var.minio_root_user : var.s3_access_key_id
  effective_s3_secret_key = var.use_minio ? local.minio_root_password : var.s3_secret_access_key
}

# This resource fails the plan if S3 config is invalid
resource "terraform_data" "validate_s3_config" {
  lifecycle {
    precondition {
      condition     = local._s3_config_valid
      error_message = "When use_minio=false, S3 variables (s3_endpoint, s3_bucket_name, s3_access_key_id, s3_secret_access_key) are required."
    }
  }
}

# =============================================================================
# S3 Object Storage (External - configured via variables)
# =============================================================================
# Note: For Bates deployment, S3 storage can be provided externally or via MinIO.
# Set use_minio=true to deploy MinIO, or configure s3_endpoint, s3_bucket_name,
# s3_access_key_id, s3_secret_access_key in your tfvars file.

# Civo object storage modules disabled - using external S3 or MinIO
# module "object_storage" { ... }
# module "pg_backup_storage" { ... }

# =============================================================================
# CloudNativePG PostgreSQL Cluster
# =============================================================================

module "attic_pg" {
  count  = var.use_cnpg_postgres ? 1 : 0
  source = "../../modules/postgresql-cnpg"

  name          = "attic-pg"
  namespace     = local.namespace_name
  database_name = "attic"
  owner_name    = "attic"
  part_of       = "nix-cache"

  # HA Configuration
  instances              = var.pg_instances
  pod_anti_affinity_type = var.pg_instances > 1 ? "required" : "preferred"

  # Storage
  storage_size  = var.pg_storage_size
  storage_class = var.pg_storage_class

  # PostgreSQL Configuration
  max_connections = var.pg_max_connections
  shared_buffers  = var.pg_shared_buffers

  # Resources
  cpu_request    = var.pg_cpu_request
  cpu_limit      = var.pg_cpu_limit
  memory_request = var.pg_memory_request
  memory_limit   = var.pg_memory_limit

  # Security - generate password
  generate_password = true

  # TLS
  enable_tls = true

  # Backup to S3 (uses MinIO if enabled, otherwise external S3)
  enable_backup = var.pg_enable_backup
  backup_s3_endpoint = var.use_minio ? (
    # MinIO internal endpoint - reuse effective_s3_endpoint for consistency
    "http://minio.${var.namespace}.svc:80"
  ) : var.s3_endpoint
  backup_s3_bucket = var.use_minio ? "pg-backup" : (
    var.pg_backup_bucket_name != "" ? var.pg_backup_bucket_name : "${var.s3_bucket_name}-pg-backup"
  )
  create_s3_credentials_secret = var.pg_enable_backup
  backup_s3_access_key_id      = local.effective_s3_access_key
  backup_s3_secret_access_key  = local.effective_s3_secret_key
  backup_retention_policy      = var.pg_backup_retention

  # Scheduled backups
  enable_scheduled_backup = var.pg_enable_backup
  backup_schedule         = var.pg_backup_schedule
  backup_immediate        = true

  # Network Policies
  enable_network_policy   = var.pg_enable_network_policy
  allowed_namespaces      = [var.namespace]
  cnpg_operator_namespace = var.cnpg_operator_namespace
  allowed_pod_labels = {
    "app.kubernetes.io/name" = "attic"
  }

  # Monitoring
  enable_monitoring = var.enable_prometheus_monitoring

  # PDB
  enable_pdb        = var.pg_instances > 1
  pdb_min_available = var.pg_instances > 2 ? "2" : "1"

  depends_on = [
    module.cnpg_operator
  ]
}

# =============================================================================
# Secrets
# =============================================================================

# Attic secrets (S3 credentials, Database URL - auth disabled)
resource "kubernetes_secret" "attic_secrets" {
  metadata {
    name      = "attic-secrets"
    namespace = local.namespace_name

    labels = {
      "app.kubernetes.io/name"       = "attic"
      "app.kubernetes.io/component"  = "secrets"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  data = {
    # PostgreSQL connection
    # Use CNPG-generated URL if using CloudNativePG, otherwise use provided URL
    DATABASE_URL = var.use_cnpg_postgres ? module.attic_pg[0].database_url : var.database_url

    # S3 credentials (MinIO or external S3)
    AWS_ACCESS_KEY_ID     = local.effective_s3_access_key
    AWS_SECRET_ACCESS_KEY = local.effective_s3_secret_key
  }

  type = "Opaque"

  depends_on = [
    module.attic_pg,
    module.minio_tenant
  ]
}

# =============================================================================
# ConfigMap - Attic Server Configuration
# =============================================================================

resource "kubernetes_config_map" "attic_config" {
  metadata {
    name      = "attic-config"
    namespace = local.namespace_name

    labels = {
      "app.kubernetes.io/name"       = "attic"
      "app.kubernetes.io/component"  = "config"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  data = {
    "server.toml" = <<-EOT
      # Attic Server Configuration
      # Generated by OpenTofu - Auth disabled for Bates internal network

      listen = "[::]:8080"

      # Auth disabled - public cache for internal use
      # require-proof-of-possession = false

      [database]
      # PostgreSQL connection (CNPG-managed cluster)
      url = "${var.use_cnpg_postgres ? module.attic_pg[0].database_url : var.database_url}"

      [storage]
      type = "s3"
      region = "${var.s3_region}"
      bucket = "${local.effective_s3_bucket}"
      endpoint = "${local.effective_s3_endpoint}"

      # JWT signing (required for internal operations even in auth-free mode)
      [jwt.signing]
      token-hs256-secret-base64 = "${local.attic_jwt_hs256_secret_base64}"

      [chunking]
      nar-size-threshold = ${var.chunking_nar_size_threshold}
      min-size = ${var.chunking_min_size}
      avg-size = ${var.chunking_avg_size}
      max-size = ${var.chunking_max_size}

      [compression]
      type = "${var.compression_type}"
      level = ${var.compression_level}

      [garbage-collection]
      interval = "${var.gc_interval}"
      default-retention-period = "${var.gc_retention_period}"
    EOT
  }

  depends_on = [
    module.minio_tenant
  ]
}

# =============================================================================
# Attic API Server Deployment (HPA-enabled)
# =============================================================================

module "attic_api" {
  source = "../../modules/hpa-deployment"

  name      = "attic"
  namespace = local.namespace_name
  image     = var.attic_image
  component = "api"

  container_port = 8080
  container_args = [
    "--config", "/etc/attic/server.toml",
    "--mode", "monolithic"
  ]

  # Environment from secrets
  env_from_secrets = [kubernetes_secret.attic_secrets.metadata[0].name]

  # Mount config file
  config_map_mounts = [{
    name       = "config"
    mount_path = "/etc/attic"
    config_map = kubernetes_config_map.attic_config.metadata[0].name
  }]

  # Resource limits
  cpu_request    = var.api_cpu_request
  cpu_limit      = var.api_cpu_limit
  memory_request = var.api_memory_request
  memory_limit   = var.api_memory_limit

  # HPA configuration
  enable_hpa            = true
  min_replicas          = var.api_min_replicas
  max_replicas          = var.api_max_replicas
  cpu_target_percent    = var.api_cpu_target_percent
  memory_target_percent = var.api_memory_target_percent

  # Scaling behavior
  scale_down_stabilization_seconds = 300
  scale_up_pods                    = 4

  # Health checks
  health_check_path       = "/" # Root endpoint returns HTML confirming service is up
  liveness_initial_delay  = 10
  liveness_period         = 30
  readiness_initial_delay = 5
  readiness_period        = 10

  # Service
  service_port = 80
  service_type = "ClusterIP"

  # Ingress
  enable_ingress          = var.enable_ingress
  ingress_host            = var.ingress_host
  ingress_class           = var.ingress_class
  enable_tls              = var.enable_tls
  cert_manager_issuer     = var.cert_manager_issuer
  ingress_proxy_body_size = "10g" # Large NAR uploads

  # Monitoring
  enable_prometheus_scrape = true
  metrics_port             = 8080
  metrics_path             = "/metrics"

  # Security - enable hardened security context
  # heywoodlh/attic image supports running as non-root user 1000
  enable_security_context = true
  run_as_user             = 1000
  run_as_group            = 1000
  fs_group                = 1000

  # HA
  enable_topology_spread = true
  enable_pdb             = true
  pdb_min_available      = "1"

  # Wait for rollout - disable for async deploys where deps may not be ready
  wait_for_rollout = var.api_wait_for_rollout

  additional_labels = {
    "app.kubernetes.io/part-of" = "nix-cache"
  }

  # Init containers to wait for dependencies (PostgreSQL and MinIO)
  init_containers = concat(
    # Wait for PostgreSQL to be ready
    var.use_cnpg_postgres ? [
      {
        name    = "wait-for-postgres"
        image   = "busybox:1.36"
        command = ["/bin/sh", "-c"]
        args = [
          "echo 'Waiting for PostgreSQL...'; until nc -z ${module.attic_pg[0].cluster_name}-rw.${local.namespace_name}.svc.cluster.local 5432; do echo 'PostgreSQL not ready, waiting...'; sleep 5; done; echo 'PostgreSQL is ready!'"
        ]
      }
    ] : [],
    # Wait for MinIO to be ready
    var.use_minio ? [
      {
        name    = "wait-for-minio"
        image   = "busybox:1.36"
        command = ["/bin/sh", "-c"]
        args = [
          "echo 'Waiting for MinIO...'; until nc -z attic-minio-hl.${local.namespace_name}.svc.cluster.local 9000; do echo 'MinIO not ready, waiting...'; sleep 5; done; echo 'MinIO is ready!'"
        ]
      }
    ] : []
  )

  # Force pod restart when config or secrets change
  pod_annotations = {
    "checksum/config" = sha256(kubernetes_config_map.attic_config.data["server.toml"])
  }

  depends_on = [
    kubernetes_secret.attic_secrets,
    module.attic_pg,
    module.minio_tenant
  ]
}

# =============================================================================
# Attic Garbage Collector Deployment (Single Replica)
# =============================================================================

resource "kubernetes_deployment" "attic_gc" {
  # Don't wait for rollout - GC may start before dependencies
  wait_for_rollout = false

  metadata {
    name      = "attic-gc"
    namespace = local.namespace_name

    labels = {
      "app.kubernetes.io/name"       = "attic-gc"
      "app.kubernetes.io/component"  = "garbage-collector"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/part-of"    = "nix-cache"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "attic-gc"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"       = "attic-gc"
          "app.kubernetes.io/component"  = "garbage-collector"
          "app.kubernetes.io/managed-by" = "opentofu"
        }
        annotations = {
          # Force pod restart when config changes
          "checksum/config" = sha256(kubernetes_config_map.attic_config.data["server.toml"])
        }
      }

      spec {
        # Init containers to wait for dependencies
        dynamic "init_container" {
          for_each = var.use_cnpg_postgres ? [1] : []
          content {
            name    = "wait-for-postgres"
            image   = "busybox:1.36"
            command = ["/bin/sh", "-c"]
            args = [
              "echo 'Waiting for PostgreSQL...'; until nc -z ${module.attic_pg[0].cluster_name}-rw.${local.namespace_name}.svc.cluster.local 5432; do echo 'PostgreSQL not ready, waiting...'; sleep 5; done; echo 'PostgreSQL is ready!'"
            ]
          }
        }

        dynamic "init_container" {
          for_each = var.use_minio ? [1] : []
          content {
            name    = "wait-for-minio"
            image   = "busybox:1.36"
            command = ["/bin/sh", "-c"]
            args = [
              "echo 'Waiting for MinIO...'; until nc -z attic-minio-hl.${local.namespace_name}.svc.cluster.local 9000; do echo 'MinIO not ready, waiting...'; sleep 5; done; echo 'MinIO is ready!'"
            ]
          }
        }

        container {
          name  = "attic-gc"
          image = var.attic_image

          args = [
            "--config", "/etc/attic/server.toml",
            "--mode", "garbage-collector"
          ]

          env_from {
            secret_ref {
              name = kubernetes_secret.attic_secrets.metadata[0].name
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/attic"
            read_only  = true
          }

          resources {
            requests = {
              memory = var.gc_memory_request
              cpu    = var.gc_cpu_request
            }
            limits = {
              memory = var.gc_memory_limit
              cpu    = var.gc_cpu_limit
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.attic_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.attic_secrets,
    module.attic_pg,
    module.minio_tenant
  ]
}

# =============================================================================
# DNS Configuration
# =============================================================================

# Determine load balancer IP (from ingress-nginx service or provided)
data "kubernetes_service" "ingress_nginx" {
  count = var.load_balancer_ip == "" && var.dns_provider != "external-dns" ? 1 : 0

  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

locals {
  # Use provided IP, or fetch from ingress-nginx, or empty for external-dns
  load_balancer_ip = var.load_balancer_ip != "" ? var.load_balancer_ip : (
    var.dns_provider != "external-dns" && length(data.kubernetes_service.ingress_nginx) > 0 ?
    data.kubernetes_service.ingress_nginx[0].status[0].load_balancer[0].ingress[0].ip :
    ""
  )

  # Build DNS records map
  dns_records = merge(
    # Production record
    var.enable_ingress ? {
      "nix-cache" = {
        type  = "A"
        value = local.load_balancer_ip
      }
    } : {},
    # Staging record (optional)
    var.enable_staging_dns ? {
      "nix-cache-staging" = {
        type  = "A"
        value = local.load_balancer_ip
      }
    } : {}
  )
}

module "dns" {
  count  = var.dns_provider != "external-dns" ? 1 : 0
  source = "../../modules/dns-record"

  provider_type = var.dns_provider
  domain        = var.domain
  records       = local.dns_records

  # Provider-specific credentials
  dreamhost_api_key = var.dreamhost_api_key

  managed_by = "attic-cache"
}

# =============================================================================
# Outputs
# =============================================================================

output "namespace" {
  description = "Kubernetes namespace for Attic"
  value       = local.namespace_name
}

output "api_service_endpoint" {
  description = "Internal service endpoint for Attic API"
  value       = module.attic_api.service_endpoint
}

output "ingress_url" {
  description = "External URL for Attic (if ingress enabled)"
  value       = module.attic_api.ingress_url
}

output "s3_bucket" {
  description = "S3 bucket name for NAR storage"
  value       = local.effective_s3_bucket
}

output "s3_endpoint" {
  description = "S3 endpoint URL"
  value       = local.effective_s3_endpoint
}

output "s3_provider" {
  description = "S3 storage provider (minio or external)"
  value       = var.use_minio ? "minio" : "external"
}

output "hpa_config" {
  description = "HPA scaling configuration"
  value       = module.attic_api.hpa_scaling_config
}

output "deployment_name" {
  description = "Name of the Attic API deployment"
  value       = module.attic_api.deployment_name
}

output "gc_deployment_name" {
  description = "Name of the Attic GC deployment"
  value       = kubernetes_deployment.attic_gc.metadata[0].name
}

# PostgreSQL outputs (CNPG)
output "pg_cluster_name" {
  description = "Name of the PostgreSQL cluster"
  value       = var.use_cnpg_postgres ? module.attic_pg[0].cluster_name : "N/A (using Neon)"
}

output "pg_host_rw" {
  description = "PostgreSQL read-write host"
  value       = var.use_cnpg_postgres ? module.attic_pg[0].host_rw : "N/A (using Neon)"
}

output "pg_host_ro" {
  description = "PostgreSQL read-only host"
  value       = var.use_cnpg_postgres ? module.attic_pg[0].host_ro : "N/A (using Neon)"
}

output "pg_credentials_secret" {
  description = "Name of secret containing PostgreSQL credentials"
  value       = var.use_cnpg_postgres ? module.attic_pg[0].credentials_secret_name : "N/A (using Neon)"
}

output "pg_database_url" {
  description = "PostgreSQL connection string"
  value       = var.use_cnpg_postgres ? module.attic_pg[0].database_url : var.database_url
  sensitive   = true
}

output "pg_backup_bucket" {
  description = "S3 bucket for PostgreSQL backups"
  value       = var.use_cnpg_postgres && var.pg_enable_backup ? (var.pg_backup_bucket_name != "" ? var.pg_backup_bucket_name : "${var.s3_bucket_name}-pg-backup") : "N/A"
}

# DNS outputs
output "dns_provider" {
  description = "DNS provider in use"
  value       = var.dns_provider
}

output "dns_records" {
  description = "DNS records created (if not using external-dns)"
  value       = var.dns_provider != "external-dns" ? module.dns[0].records : {}
}

output "dns_fqdns" {
  description = "Fully qualified domain names"
  value       = var.dns_provider != "external-dns" ? module.dns[0].fqdns : [var.ingress_host]
}

output "load_balancer_ip" {
  description = "Load balancer IP address"
  value       = local.load_balancer_ip
}

# MinIO outputs
output "minio_enabled" {
  description = "Whether MinIO is enabled for S3 storage"
  value       = var.use_minio
}

output "minio_tenant_name" {
  description = "Name of the MinIO tenant"
  value       = var.use_minio ? module.minio_tenant[0].tenant_name : "N/A"
}

output "minio_distributed_mode" {
  description = "Whether MinIO is running in distributed mode"
  value       = var.use_minio ? module.minio_tenant[0].distributed_mode : false
}

output "minio_storage_total" {
  description = "Total MinIO storage capacity"
  value       = var.use_minio ? module.minio_tenant[0].storage_total : "N/A"
}

output "bazel_cache_enabled" {
  description = "Whether Bazel cache is enabled"
  value       = var.enable_bazel_cache && var.use_minio
}

output "bazel_cache_grpc_endpoint" {
  description = "Bazel cache gRPC endpoint (cluster-internal)"
  value       = var.enable_bazel_cache && var.use_minio ? module.bazel_cache[0].grpc_endpoint : null
}

output "bazel_cache_http_endpoint" {
  description = "Bazel cache HTTP endpoint (status/metrics)"
  value       = var.enable_bazel_cache && var.use_minio ? module.bazel_cache[0].http_endpoint : null
}

output "bazel_cache_bazelrc_config" {
  description = "Configuration lines for .bazelrc (CI-internal use)"
  value       = var.enable_bazel_cache && var.use_minio ? module.bazel_cache[0].bazelrc_config : null
}

# =============================================================================
# Cache Warming CronJob (Optional)
# =============================================================================

resource "kubernetes_cron_job_v1" "cache_warm" {
  count = var.enable_cache_warming ? 1 : 0

  metadata {
    name      = "attic-cache-warm"
    namespace = local.namespace_name

    labels = {
      "app.kubernetes.io/name"       = "attic-cache-warm"
      "app.kubernetes.io/component"  = "cache-warming"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/part-of"    = "nix-cache"
    }
  }

  spec {
    schedule                      = "0 2 * * *" # Daily at 2 AM
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "attic-cache-warm"
          "app.kubernetes.io/component" = "cache-warming"
        }
      }

      spec {
        ttl_seconds_after_finished = 3600

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name"      = "attic-cache-warm"
              "app.kubernetes.io/component" = "cache-warming"
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
              name  = "warm"
              image = "nixos/nix:latest"

              command = ["/bin/sh", "-c"]
              args = [
                <<-EOT
                  set -e
                  echo "Warming cache with common flake inputs..."

                  # Pre-fetch common Nix flake inputs
                  nix flake prefetch github:NixOS/nixpkgs/nixos-unstable || echo "Failed to prefetch nixpkgs"
                  nix flake prefetch github:nix-community/home-manager || echo "Failed to prefetch home-manager"

                  echo "Cache warming complete"
                EOT
              ]

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "1Gi"
                }
              }

              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = false
                capabilities {
                  drop = ["ALL"]
                }
              }
            }
          }
        }
      }
    }
  }
}

# =============================================================================
# Cache Initialization Job
# =============================================================================
# Creates the 'main' cache after deployment. Runs once per apply.
# Generates a short-lived JWT at runtime from the HS256 signing key,
# then calls the Attic API to create (or verify) the cache.

resource "kubernetes_job_v1" "init_cache" {
  metadata {
    name      = "attic-init-cache-${substr(sha256(var.attic_image), 0, 8)}"
    namespace = local.namespace_name

    labels = {
      "app.kubernetes.io/name"       = "attic-init-cache"
      "app.kubernetes.io/component"  = "initialization"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/part-of"    = "nix-cache"
    }
  }

  spec {
    ttl_seconds_after_finished = 300
    backoff_limit              = 3

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "attic-init-cache"
          "app.kubernetes.io/component" = "initialization"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "init"
          image = "alpine:3.19"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              set -e
              apk add --no-cache curl openssl >/dev/null 2>&1

              ATTIC_URL="http://attic.${local.namespace_name}.svc.cluster.local"

              echo "Waiting for Attic API..."
              until curl -sf "$ATTIC_URL/" >/dev/null 2>&1; do
                echo "  not ready, waiting 5s..."
                sleep 5
              done
              echo "Attic API is up"

              # Generate a short-lived JWT from the HS256 signing key
              SECRET=$(echo -n "$ATTIC_JWT_HS256_SECRET_B64" | base64 -d)
              b64url() { base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

              HEADER=$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)
              EXP=$(( $(date +%s) + 3600 ))
              PAYLOAD=$(printf '{"sub":"init-cache","exp":%d,"https://jwt.attic.rs/v1":{"caches":{"*":{"r":1,"w":1,"cc":1}}}}' "$EXP" | b64url)
              SIG=$(printf '%s.%s' "$HEADER" "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)
              TOKEN="$HEADER.$PAYLOAD.$SIG"

              echo "Creating 'main' cache..."
              HTTP_CODE=$(curl -s -o /tmp/resp -w '%%{http_code}' \
                -X POST "$ATTIC_URL/_api/v1/cache-config/main" \
                -H 'Content-Type: application/json' \
                -H "Authorization: Bearer $TOKEN" \
                -d '{"is_public":true,"store_dir":"/nix/store","priority":41,"upstream_cache_key_names":[],"keypair":"Generate"}')

              case "$HTTP_CODE" in
                200|201) echo "Cache 'main' created (HTTP $HTTP_CODE)" ;;
                409)     echo "Cache 'main' already exists" ;;
                *)       echo "Response: $HTTP_CODE"; cat /tmp/resp 2>/dev/null; echo ;;
              esac

              curl -sf "$ATTIC_URL/main/nix-cache-info" && echo "Cache verified!" || echo "Verification pending"
            EOT
          ]

          env {
            name = "ATTIC_JWT_HS256_SECRET_B64"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.attic_jwt_signing.metadata[0].name
                key  = "hs256-secret-base64"
              }
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [module.attic_api]
}

# =============================================================================
# Bazel Remote Cache
# =============================================================================
# Optional bazel-remote cache server for Bazel action caching.
# Uses the same MinIO backend as Attic for storage.

# S3 credentials secret for bazel-cache (reuses MinIO credentials)
resource "kubernetes_secret_v1" "bazel_cache_s3" {
  count = var.enable_bazel_cache && var.use_minio ? 1 : 0

  metadata {
    name      = "bazel-cache-s3-credentials"
    namespace = local.namespace_name
    labels = {
      "app.kubernetes.io/name"       = "bazel-cache"
      "app.kubernetes.io/component"  = "storage-credentials"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  data = {
    "access-key" = local.effective_s3_access_key
    "secret-key" = local.effective_s3_secret_key
  }

  depends_on = [
    kubernetes_namespace.nix_cache,
    kubernetes_secret.minio_credentials
  ]
}

# Bazel remote cache module
module "bazel_cache" {
  count  = var.enable_bazel_cache && var.use_minio ? 1 : 0
  source = "../../modules/bazel-cache"

  name      = "bazel-cache"
  namespace = local.namespace_name

  # MinIO S3 backend
  s3_endpoint    = local.effective_s3_endpoint
  s3_bucket      = var.bazel_cache_bucket
  s3_secret      = kubernetes_secret_v1.bazel_cache_s3[0].metadata[0].name
  s3_disable_ssl = true

  # Cache configuration
  max_cache_size_gb = var.bazel_cache_max_size_gb

  # Scaling
  min_replicas = var.bazel_cache_min_replicas
  max_replicas = var.bazel_cache_max_replicas

  # Resources
  cpu_request    = var.bazel_cache_cpu_request
  memory_request = var.bazel_cache_memory_request
  cpu_limit      = var.bazel_cache_cpu_limit
  memory_limit   = var.bazel_cache_memory_limit

  # Ingress (optional)
  enable_ingress = var.bazel_cache_enable_ingress
  ingress_host   = var.bazel_cache_ingress_host != "" ? var.bazel_cache_ingress_host : "bazel-cache.${var.ingress_domain}"

  # Monitoring
  enable_metrics         = var.enable_prometheus_monitoring
  create_service_monitor = var.enable_prometheus_monitoring

  # Don't wait for rollout to avoid blocking
  wait_for_rollout = false

  # Init container to wait for MinIO to be ready
  init_containers = [
    {
      name    = "wait-for-minio"
      image   = "busybox:1.36"
      command = ["/bin/sh", "-c"]
      args = [
        "echo 'Waiting for MinIO...'; until nc -z attic-minio-hl.${local.namespace_name}.svc.cluster.local 9000; do echo 'MinIO not ready, waiting...'; sleep 5; done; echo 'MinIO is ready!'"
      ]
    }
  ]

  depends_on = [
    module.minio_tenant,
    kubernetes_secret_v1.bazel_cache_s3
  ]
}

# =============================================================================
# JWT Signing Key Output
# =============================================================================
# The signing key can be used to generate push/pull tokens for CI.
# See: scripts/generate-attic-token.sh

output "jwt_signing_secret_base64" {
  description = "Base64-encoded HS256 JWT signing secret (use with scripts/generate-attic-token.sh)"
  value       = local.attic_jwt_hs256_secret_base64
  sensitive   = true
}

output "jwt_signing_k8s_secret" {
  description = "K8s secret name containing the JWT signing key"
  value       = kubernetes_secret.attic_jwt_signing.metadata[0].name
}
