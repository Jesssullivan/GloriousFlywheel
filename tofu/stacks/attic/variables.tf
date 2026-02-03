# Attic Stack - Variables
#
# Configuration variables for the Attic Nix binary cache deployment.

# =============================================================================
# Kubernetes Authentication
# =============================================================================

variable "k8s_host" {
  description = "Kubernetes API server URL"
  type        = string
  default     = ""
}

variable "k8s_client_cert" {
  description = "Client certificate for Kubernetes auth (Civo/RKE2)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "k8s_client_key" {
  description = "Client key for Kubernetes auth (Civo/RKE2)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "k8s_ca_cert" {
  description = "CA certificate for Kubernetes API"
  type        = string
  default     = ""
  sensitive   = true
}

variable "k8s_token" {
  description = "Bearer token for Kubernetes auth (DOKS)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "k8s_config_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "k8s_config_context" {
  description = "Kubeconfig context to use"
  type        = string
  default     = ""
}

variable "k8s_insecure" {
  description = "Skip TLS verification (for self-signed certs)"
  type        = bool
  default     = false
}

# =============================================================================
# Civo Configuration
# =============================================================================

variable "civo_api_key" {
  description = "Civo API key for object storage provisioning"
  type        = string
  sensitive   = true
}

variable "civo_region" {
  description = "Civo region"
  type        = string
  default     = "NYC1"

  validation {
    condition     = contains(["NYC1", "LON1", "FRA1", "PHX1"], var.civo_region)
    error_message = "civo_region must be one of: NYC1, LON1, FRA1, PHX1"
  }
}

# =============================================================================
# Namespace & Environment
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for Attic deployment"
  type        = string
  default     = "nix-cache"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "environment must be one of: production, staging, development"
  }
}

variable "adopt_existing_namespace" {
  description = "Adopt existing namespace instead of creating new one. Use when namespace already exists (e.g., from manual creation or previous partial deployment)"
  type        = bool
  default     = false
}

variable "adopt_existing_object_store" {
  description = "Adopt existing Civo object store credentials instead of creating new ones"
  type        = bool
  default     = false
}

variable "deploy_version" {
  description = "Deployment version tag (for rollback tracking)"
  type        = string
  default     = ""
}

# =============================================================================
# Attic Image Configuration
# =============================================================================

variable "attic_image" {
  description = "Attic container image (pinned to specific commit for security)"
  type        = string
  # Pinned to commit 12cbeca (2026-01-22) for reproducibility and security
  # Update this when upgrading Attic version after testing
  default     = "heywoodlh/attic:12cbeca141f46e1ade76728bce8adc447f2166c6"
}

# =============================================================================
# Database Configuration (Legacy - Neon)
# =============================================================================

variable "database_url" {
  description = "PostgreSQL connection string for Attic metadata (required if use_cnpg_postgres is false)"
  type        = string
  default     = "postgresql://placeholder:placeholder@localhost/attic"
  sensitive   = true

  validation {
    condition     = can(regex("^postgresql://", var.database_url))
    error_message = "database_url must be a valid PostgreSQL connection string"
  }
}

# =============================================================================
# PostgreSQL Configuration (CloudNativePG)
# =============================================================================

variable "use_cnpg_postgres" {
  description = "Use CloudNativePG PostgreSQL instead of Neon"
  type        = bool
  default     = true
}

variable "cnpg_operator_namespace" {
  description = "Namespace for CloudNativePG operator"
  type        = string
  default     = "cnpg-system"
}

variable "cnpg_chart_version" {
  description = "CloudNativePG Helm chart version"
  type        = string
  default     = "0.20.0"
}

variable "install_cnpg_operator" {
  description = "Install CNPG operator (set to false if already installed)"
  type        = bool
  default     = true
}

variable "pg_instances" {
  description = "Number of PostgreSQL instances (1=standalone, 3=HA)"
  type        = number
  default     = 3

  validation {
    condition     = var.pg_instances >= 1 && var.pg_instances <= 10
    error_message = "pg_instances must be between 1 and 10"
  }
}

variable "pg_storage_size" {
  description = "Storage size for each PostgreSQL instance"
  type        = string
  default     = "10Gi"
}

variable "pg_storage_class" {
  description = "Kubernetes storage class for PostgreSQL"
  type        = string
  default     = "civo-volume"
}

variable "pg_max_connections" {
  description = "Maximum database connections"
  type        = number
  default     = 100

  validation {
    condition     = var.pg_max_connections >= 10 && var.pg_max_connections <= 10000
    error_message = "pg_max_connections must be between 10 and 10000"
  }
}

variable "pg_shared_buffers" {
  description = "PostgreSQL shared_buffers setting"
  type        = string
  default     = "256MB"
}

variable "pg_cpu_request" {
  description = "CPU request for each PostgreSQL instance"
  type        = string
  default     = "250m"
}

variable "pg_cpu_limit" {
  description = "CPU limit for each PostgreSQL instance"
  type        = string
  default     = "1000m"
}

variable "pg_memory_request" {
  description = "Memory request for each PostgreSQL instance"
  type        = string
  default     = "512Mi"
}

variable "pg_memory_limit" {
  description = "Memory limit for each PostgreSQL instance"
  type        = string
  default     = "1Gi"
}

variable "pg_enable_network_policy" {
  description = "Enable network policies for PostgreSQL. Note: Disabled by default due to K3s API server egress issues - CNPG initdb requires unrestricted API access."
  type        = bool
  default     = false
}

# =============================================================================
# PostgreSQL Backup Configuration
# =============================================================================

variable "pg_enable_backup" {
  description = "Enable backup to Civo Object Storage"
  type        = bool
  default     = true
}

variable "pg_backup_bucket_name" {
  description = "S3 bucket name for PostgreSQL backups (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "pg_backup_max_size_gb" {
  description = "Maximum size for PostgreSQL backup bucket (GB)"
  type        = number
  default     = 500

  validation {
    condition     = var.pg_backup_max_size_gb >= 500
    error_message = "pg_backup_max_size_gb must be at least 500 (Civo minimum)"
  }
}

variable "pg_backup_retention" {
  description = "Backup retention period"
  type        = string
  default     = "30d"
}

variable "pg_backup_schedule" {
  description = "Backup schedule in cron format"
  type        = string
  default     = "0 0 * * *" # Daily at midnight
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "enable_prometheus_monitoring" {
  description = "Enable Prometheus monitoring for CNPG and Attic"
  type        = bool
  default     = true
}

# =============================================================================
# S3 Storage Configuration
# =============================================================================

variable "s3_bucket_name" {
  description = "S3 bucket name (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "s3_max_size_gb" {
  description = "Maximum S3 bucket size in GB"
  type        = number
  default     = 500

  validation {
    condition     = var.s3_max_size_gb >= 500
    error_message = "s3_max_size_gb must be at least 500 (Civo minimum)"
  }
}

variable "create_s3_credentials" {
  description = "Create new S3 credentials"
  type        = bool
  default     = true
}

variable "s3_access_key_id" {
  description = "Existing S3 access key ID (required if create_s3_credentials is false)"
  type        = string
  default     = ""
}

# =============================================================================
# Attic Authentication
# =============================================================================

variable "attic_jwt_secret_base64" {
  description = "Base64-encoded RSA private key for JWT signing"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.attic_jwt_secret_base64) > 0
    error_message = "attic_jwt_secret_base64 is required"
  }
}

# =============================================================================
# Attic Chunking Configuration
# =============================================================================

variable "chunking_nar_size_threshold" {
  description = "NAR size threshold for chunking (bytes)"
  type        = number
  default     = 65536 # 64 KiB
}

variable "chunking_min_size" {
  description = "Minimum chunk size (bytes)"
  type        = number
  default     = 16384 # 16 KiB
}

variable "chunking_avg_size" {
  description = "Average chunk size (bytes)"
  type        = number
  default     = 65536 # 64 KiB
}

variable "chunking_max_size" {
  description = "Maximum chunk size (bytes)"
  type        = number
  default     = 262144 # 256 KiB
}

# =============================================================================
# Attic Compression Configuration
# =============================================================================

variable "compression_type" {
  description = "Compression algorithm (zstd, none)"
  type        = string
  default     = "zstd"

  validation {
    condition     = contains(["zstd", "none"], var.compression_type)
    error_message = "compression_type must be 'zstd' or 'none'"
  }
}

variable "compression_level" {
  description = "Compression level (1-22 for zstd)"
  type        = number
  default     = 8

  validation {
    condition     = var.compression_level >= 1 && var.compression_level <= 22
    error_message = "compression_level must be between 1 and 22"
  }
}

# =============================================================================
# Garbage Collection Configuration
# =============================================================================

variable "gc_interval" {
  description = "Garbage collection interval"
  type        = string
  default     = "12 hours"
}

variable "gc_retention_period" {
  description = "Default retention period for cached objects"
  type        = string
  default     = "3 months"
}

# =============================================================================
# API Server Resources
# =============================================================================

variable "api_cpu_request" {
  description = "CPU request for API server"
  type        = string
  default     = "100m"
}

variable "api_cpu_limit" {
  description = "CPU limit for API server"
  type        = string
  default     = "1000m"
}

variable "api_memory_request" {
  description = "Memory request for API server"
  type        = string
  default     = "128Mi"
}

variable "api_memory_limit" {
  description = "Memory limit for API server"
  type        = string
  default     = "512Mi"
}

# =============================================================================
# API Server HPA Configuration
# =============================================================================

variable "api_min_replicas" {
  description = "Minimum API server replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.api_min_replicas >= 1
    error_message = "api_min_replicas must be at least 1"
  }
}

variable "api_max_replicas" {
  description = "Maximum API server replicas"
  type        = number
  default     = 10

  validation {
    condition     = var.api_max_replicas >= 1
    error_message = "api_max_replicas must be at least 1"
  }
}

variable "api_cpu_target_percent" {
  description = "CPU utilization target for HPA scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.api_cpu_target_percent >= 0 && var.api_cpu_target_percent <= 100
    error_message = "api_cpu_target_percent must be between 0 and 100"
  }
}

variable "api_memory_target_percent" {
  description = "Memory utilization target for HPA scaling"
  type        = number
  default     = 80

  validation {
    condition     = var.api_memory_target_percent >= 0 && var.api_memory_target_percent <= 100
    error_message = "api_memory_target_percent must be between 0 and 100"
  }
}

# =============================================================================
# GC Worker Resources
# =============================================================================

variable "gc_cpu_request" {
  description = "CPU request for GC worker"
  type        = string
  default     = "50m"
}

variable "gc_cpu_limit" {
  description = "CPU limit for GC worker"
  type        = string
  default     = "500m"
}

variable "gc_memory_request" {
  description = "Memory request for GC worker"
  type        = string
  default     = "64Mi"
}

variable "gc_memory_limit" {
  description = "Memory limit for GC worker"
  type        = string
  default     = "256Mi"
}

# =============================================================================
# Ingress Configuration
# =============================================================================

variable "enable_ingress" {
  description = "Enable ingress for external access"
  type        = bool
  default     = true
}

variable "ingress_host" {
  description = "Hostname for ingress"
  type        = string
  default     = "nix-cache.fuzzy-dev.tinyland.dev"
}

variable "ingress_class" {
  description = "Ingress class (traefik, nginx)"
  type        = string
  default     = "nginx"  # Civo clusters use nginx-ingress by default
}

variable "enable_tls" {
  description = "Enable TLS for ingress"
  type        = bool
  default     = true
}

variable "cert_manager_issuer" {
  description = "cert-manager ClusterIssuer name"
  type        = string
  default     = "letsencrypt-prod"
}

# =============================================================================
# DNS Configuration
# =============================================================================

variable "dns_provider" {
  description = "DNS provider (dreamhost, external-dns)"
  type        = string
  default     = "external-dns"

  validation {
    condition     = contains(["dreamhost", "external-dns"], var.dns_provider)
    error_message = "dns_provider must be one of: dreamhost, external-dns"
  }
}

variable "domain" {
  description = "Base domain for DNS records"
  type        = string
  default     = "fuzzy-dev.tinyland.dev"
}

variable "dreamhost_api_key" {
  description = "DreamHost API key (required if dns_provider is dreamhost)"
  type        = string
  default     = ""
  sensitive   = true
}

# Note: Cloudflare support removed - use external-dns with Cloudflare webhook if needed

variable "enable_staging_dns" {
  description = "Create staging DNS record"
  type        = bool
  default     = false
}

variable "staging_ingress_host" {
  description = "Hostname for staging ingress"
  type        = string
  default     = "nix-cache-staging.fuzzy-dev.tinyland.dev"
}

variable "load_balancer_ip" {
  description = "Load balancer IP for DNS records (auto-detected if empty)"
  type        = string
  default     = ""
}

# =============================================================================
# Token Management Configuration
# =============================================================================

variable "enable_token_management" {
  description = "Enable the token management module"
  type        = bool
  default     = true
}

variable "ci_token_validity_days" {
  description = "Validity period for CI tokens in days"
  type        = number
  default     = 90

  validation {
    condition     = var.ci_token_validity_days >= 1 && var.ci_token_validity_days <= 365
    error_message = "ci_token_validity_days must be between 1 and 365"
  }
}

variable "service_token_validity_days" {
  description = "Validity period for service tokens in days"
  type        = number
  default     = 365

  validation {
    condition     = var.service_token_validity_days >= 1 && var.service_token_validity_days <= 730
    error_message = "service_token_validity_days must be between 1 and 730"
  }
}

variable "root_token_validity_days" {
  description = "Validity period for root token in days"
  type        = number
  default     = 180

  validation {
    condition     = var.root_token_validity_days >= 1 && var.root_token_validity_days <= 365
    error_message = "root_token_validity_days must be between 1 and 365"
  }
}

variable "ci_tokens" {
  description = "Map of CI tokens to create. Key is token name, value is config."
  type = map(object({
    permissions = list(string)
    caches      = list(string)
    description = optional(string, "")
  }))
  default = {
    "gitlab-tinyland-gnucashr" = {
      permissions = ["push", "pull"]
      caches      = ["main"]
      description = "CI token for tinyland/projects/gnucashr"
    }
    "gitlab-tinyland-attic-cache" = {
      permissions = ["push", "pull"]
      caches      = ["main"]
      description = "CI token for tinyland/projects/attic-cache"
    }
    "github-jesssullivan-gnucashr" = {
      permissions = ["push", "pull"]
      caches      = ["main"]
      description = "CI token for jesssullivan/gnucashr on GitHub"
    }
  }

  validation {
    condition = alltrue([
      for name, config in var.ci_tokens :
      alltrue([for perm in config.permissions : contains(["push", "pull", "delete", "admin"], perm)])
    ])
    error_message = "permissions must be one of: push, pull, delete, admin"
  }
}

variable "readonly_tokens" {
  description = "Map of read-only tokens to create. Key is token name, value is config."
  type = map(object({
    caches      = list(string)
    description = optional(string, "")
  }))
  default = {
    "public-pull" = {
      caches      = ["main"]
      description = "Public read-only access to main cache"
    }
  }
}

variable "service_tokens" {
  description = "Map of service tokens to create. Key is token name, value is config."
  type = map(object({
    permissions = list(string)
    caches      = list(string)
    description = optional(string, "")
  }))
  default = {
    "gc-worker" = {
      permissions = ["admin"]
      caches      = ["main"]
      description = "Garbage collector worker token"
    }
  }

  validation {
    condition = alltrue([
      for name, config in var.service_tokens :
      alltrue([for perm in config.permissions : contains(["push", "pull", "delete", "admin", "*"], perm)])
    ])
    error_message = "permissions must be one of: push, pull, delete, admin, *"
  }
}

variable "create_root_token" {
  description = "Whether to create a root admin token"
  type        = bool
  default     = true
}

variable "revoked_token_ids" {
  description = "List of revoked token IDs (JTI claims)"
  type        = list(string)
  default     = []
}

variable "revocation_list_revision" {
  description = "Revision number for the revocation list"
  type        = number
  default     = 1
}

variable "create_token_accessor_sa" {
  description = "Create a ServiceAccount with read access to tokens"
  type        = bool
  default     = true
}
