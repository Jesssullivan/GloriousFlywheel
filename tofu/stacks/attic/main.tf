# Attic Stack - Nix Binary Cache Deployment
#
# Deploys Attic (self-hosted Nix binary cache) to Civo Kubernetes
# with S3 backend, CloudNativePG PostgreSQL, and HPA autoscaling.
#
# Architecture:
#   - Attic API Server: Stateless, HPA-enabled (2-10 replicas)
#   - Attic GC Worker: Single replica for garbage collection
#   - PostgreSQL: CloudNativePG HA cluster (3 nodes) OR Neon serverless (legacy)
#   - S3 Storage: Civo Object Storage (NAR/chunk storage)
#
# Usage:
#   cd tofu/stacks/attic
#   tofu init
#   tofu plan -var-file=terraform.tfvars
#   tofu apply -var-file=terraform.tfvars

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
    civo = {
      source  = "civo/civo"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# Kubernetes Provider Configuration
# =============================================================================

provider "kubernetes" {
  # Priority 1: Explicit host + client cert (Civo k3s)
  host                   = var.k8s_host
  client_certificate     = var.k8s_client_cert
  client_key             = var.k8s_client_key
  cluster_ca_certificate = var.k8s_ca_cert

  # Priority 2: Explicit host + token (DOKS)
  token = var.k8s_token

  # Priority 3: Kubeconfig file
  config_path    = var.k8s_config_path
  config_context = var.k8s_config_context

  # TLS verification (disable for self-signed certs)
  insecure = var.k8s_insecure
}

provider "helm" {
  kubernetes {
    host                   = var.k8s_host
    client_certificate     = var.k8s_client_cert
    client_key             = var.k8s_client_key
    cluster_ca_certificate = var.k8s_ca_cert
    token                  = var.k8s_token
    config_path            = var.k8s_config_path
    config_context         = var.k8s_config_context
    insecure               = var.k8s_insecure
  }
}

provider "civo" {
  token  = var.civo_api_key
  region = var.civo_region
}

provider "kubectl" {
  host                   = var.k8s_host
  client_certificate     = var.k8s_client_cert
  client_key             = var.k8s_client_key
  cluster_ca_certificate = var.k8s_ca_cert
  token                  = var.k8s_token
  config_path            = var.k8s_config_path
  config_context         = var.k8s_config_context
  load_config_file       = var.k8s_config_path != "" ? true : false
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
# CloudNativePG Operator (Cluster-Wide)
# =============================================================================

module "cnpg_operator" {
  count  = var.use_cnpg_postgres && var.install_cnpg_operator ? 1 : 0
  source = "../../modules/cnpg-operator"

  namespace        = var.cnpg_operator_namespace
  create_namespace = true
  chart_version    = var.cnpg_chart_version

  operator_replicas       = 1
  operator_cpu_request    = "100m"
  operator_memory_request = "128Mi"

  enable_pod_monitor       = var.enable_prometheus_monitoring
  enable_grafana_dashboard = false
}

# =============================================================================
# Civo Object Storage (S3 Backend for NAR Storage)
# =============================================================================

module "object_storage" {
  source = "../../modules/civo-object-store"

  # Include environment to ensure unique credential names across staging/production
  name        = "nix-cache-${var.environment}"
  bucket_name = var.s3_bucket_name
  region      = var.civo_region
  max_size_gb = var.s3_max_size_gb

  create_credentials = var.create_s3_credentials
  access_key_id      = var.s3_access_key_id

  additional_labels = {
    "project" = "attic"
    "env"     = var.environment
  }
}

# =============================================================================
# Civo Object Storage (S3 Backend for PostgreSQL Backups)
# =============================================================================

module "pg_backup_storage" {
  count  = var.use_cnpg_postgres && var.pg_enable_backup ? 1 : 0
  source = "../../modules/civo-object-store"

  # Include environment to ensure unique credential names across staging/production
  name        = "attic-pg-backup-${var.environment}"
  bucket_name = var.pg_backup_bucket_name
  region      = var.civo_region
  max_size_gb = var.pg_backup_max_size_gb

  create_credentials = true

  additional_labels = {
    "project" = "attic"
    "env"     = var.environment
    "purpose" = "postgresql-backup"
  }
}

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

  # Backup to S3
  enable_backup                = var.pg_enable_backup
  backup_s3_endpoint           = var.pg_enable_backup ? module.pg_backup_storage[0].endpoint_url : ""
  backup_s3_bucket             = var.pg_enable_backup ? module.pg_backup_storage[0].bucket_name : ""
  create_s3_credentials_secret = var.pg_enable_backup
  backup_s3_access_key_id      = var.pg_enable_backup ? module.pg_backup_storage[0].access_key_id : ""
  backup_s3_secret_access_key  = var.pg_enable_backup ? module.pg_backup_storage[0].secret_access_key : ""
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
  enable_pdb       = var.pg_instances > 1
  pdb_min_available = var.pg_instances > 2 ? "2" : "1"

  depends_on = [
    module.cnpg_operator
  ]
}

# =============================================================================
# Secrets
# =============================================================================

# Attic secrets (S3 credentials, JWT signing key, Database URL)
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
    # JWT signing key (RS256)
    ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64 = var.attic_jwt_secret_base64

    # PostgreSQL connection
    # Use CNPG-generated URL if using CloudNativePG, otherwise use provided URL
    DATABASE_URL = var.use_cnpg_postgres ? module.attic_pg[0].database_url : var.database_url

    # S3 credentials
    AWS_ACCESS_KEY_ID     = module.object_storage.access_key_id
    AWS_SECRET_ACCESS_KEY = module.object_storage.secret_access_key
  }

  type = "Opaque"

  depends_on = [module.attic_pg]
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
      # Generated by OpenTofu

      listen = "[::]:8080"

      # Token signing - uses ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64 env var
      # token-rs256-secret-base64 is set via environment variable

      [database]
      # Uses DATABASE_URL environment variable

      [storage]
      type = "s3"
      region = "${var.civo_region}"
      bucket = "${module.object_storage.bucket_name}"
      endpoint = "${module.object_storage.endpoint_url}"

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
    "--mode", "api-server"
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
  health_check_path       = "/"  # Root endpoint returns HTML confirming service is up
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
  run_as_user  = 1000
  run_as_group = 1000
  fs_group     = 1000

  # HA
  enable_topology_spread = true
  enable_pdb             = true
  pdb_min_available      = "1"

  additional_labels = {
    "app.kubernetes.io/part-of" = "nix-cache"
  }

  depends_on = [
    kubernetes_secret.attic_secrets,
    module.attic_pg
  ]
}

# =============================================================================
# Attic Garbage Collector Deployment (Single Replica)
# =============================================================================

resource "kubernetes_deployment" "attic_gc" {
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
      }

      spec {
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
    module.attic_pg
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
  value       = module.object_storage.bucket_name
}

output "s3_endpoint" {
  description = "S3 endpoint URL"
  value       = module.object_storage.endpoint_url
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
  value       = var.use_cnpg_postgres && var.pg_enable_backup ? module.pg_backup_storage[0].bucket_name : "N/A"
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

# =============================================================================
# Attic Token Management
# =============================================================================

module "attic_tokens" {
  count  = var.enable_token_management ? 1 : 0
  source = "../../modules/attic-tokens"

  namespace   = local.namespace_name
  environment = var.environment
  part_of     = "nix-cache"

  # Token validity periods
  ci_token_validity_days      = var.ci_token_validity_days
  service_token_validity_days = var.service_token_validity_days
  root_token_validity_days    = var.root_token_validity_days

  # CI tokens for each repository
  ci_tokens = var.ci_tokens

  # Read-only tokens for public access
  readonly_tokens = var.readonly_tokens

  # Service tokens for internal operations
  service_tokens = var.service_tokens

  # Root token
  create_root_token = var.create_root_token

  # Token revocation
  revoked_token_ids        = var.revoked_token_ids
  revocation_list_revision = var.revocation_list_revision

  # RBAC
  create_token_accessor_sa = var.create_token_accessor_sa

  additional_labels = {
    "app.kubernetes.io/part-of" = "nix-cache"
  }

  # Namespace dependency handled via local.namespace_name reference
}

# =============================================================================
# Token Management Outputs
# =============================================================================

output "token_management_enabled" {
  description = "Whether token management module is enabled"
  value       = var.enable_token_management
}

output "ci_token_ids" {
  description = "Map of CI token names to their IDs (for revocation)"
  value       = var.enable_token_management ? module.attic_tokens[0].ci_token_ids : {}
}

output "ci_tokens_secret_name" {
  description = "Name of the Kubernetes secret containing CI tokens"
  value       = var.enable_token_management ? module.attic_tokens[0].ci_tokens_secret_name : "N/A"
}

output "ci_tokens" {
  description = "Map of CI token names to their secrets"
  value       = var.enable_token_management ? module.attic_tokens[0].ci_tokens : {}
  sensitive   = true
}

output "readonly_tokens" {
  description = "Map of read-only token names to their secrets"
  value       = var.enable_token_management ? module.attic_tokens[0].readonly_tokens : {}
  sensitive   = true
}

output "service_tokens" {
  description = "Map of service token names to their secrets"
  value       = var.enable_token_management ? module.attic_tokens[0].service_tokens : {}
  sensitive   = true
}

output "root_token" {
  description = "Root admin token"
  value       = var.enable_token_management && var.create_root_token ? module.attic_tokens[0].root_token : null
  sensitive   = true
}

output "token_rotation_schedule" {
  description = "Token rotation schedule information"
  value = var.enable_token_management ? {
    ci_tokens = {
      last_rotation = module.attic_tokens[0].ci_token_rotation_date
      next_rotation = module.attic_tokens[0].ci_token_next_rotation
    }
    service_tokens = {
      last_rotation = module.attic_tokens[0].service_token_rotation_date
      next_rotation = module.attic_tokens[0].service_token_next_rotation
    }
    root_token = {
      last_rotation = module.attic_tokens[0].root_token_rotation_date
      next_rotation = module.attic_tokens[0].root_token_next_rotation
    }
  } : null
}

output "token_summary" {
  description = "Summary of all generated tokens (no secrets)"
  value       = var.enable_token_management ? module.attic_tokens[0].token_summary : null
}
