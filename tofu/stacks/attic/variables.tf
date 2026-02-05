# Attic Stack - Variables
#
# Configuration variables for the Attic Nix binary cache deployment.
# Bates College deployment - auth-free mode for internal network.

# =============================================================================
# Kubernetes Authentication (GitLab Kubernetes Agent)
# =============================================================================

variable "k8s_config_path" {
  description = "Path to kubeconfig file (usually set by GitLab CI)"
  type        = string
  default     = ""
}

variable "cluster_context" {
  description = "GitLab Kubernetes Agent context (e.g., bates-ils/projects/kubernetes/gitlab-agents:beehive)"
  type        = string

  validation {
    condition     = can(regex("^bates-ils/projects/kubernetes/gitlab-agents:(beehive|rigel)$", var.cluster_context))
    error_message = "cluster_context must be a valid Bates GitLab Agent context (beehive or rigel)"
  }
}

variable "ingress_domain" {
  description = "Base domain for ingress (beehive.bates.edu or rigel.bates.edu)"
  type        = string
  default     = "beehive.bates.edu"
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
  default = "heywoodlh/attic:12cbeca141f46e1ade76728bce8adc447f2166c6"
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

variable "cnpg_operator_create_namespace" {
  description = "Create the CNPG operator namespace (set false if namespace exists)"
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
  default     = "trident-expandable-delete"
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
# S3 Storage Configuration (Optional when using MinIO)
# =============================================================================
# When use_minio=true, MinIO provides S3-compatible storage internally.
# These variables are only required when use_minio=false.

variable "s3_endpoint" {
  description = "S3 endpoint URL (required if use_minio=false)"
  type        = string
  default     = ""
}

variable "s3_region" {
  description = "S3 region"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for NAR storage (required if use_minio=false)"
  type        = string
  default     = ""
}

variable "s3_access_key_id" {
  description = "S3 access key ID (required if use_minio=false)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "s3_secret_access_key" {
  description = "S3 secret access key (required if use_minio=false)"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# Attic Authentication (DISABLED)
# =============================================================================
# Authentication is disabled for Bates internal network deployment.
# The cache operates in public read/write mode.

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

variable "api_wait_for_rollout" {
  description = "Wait for API deployment rollout (set false if deps may not be ready)"
  type        = bool
  default     = true
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
  description = "Hostname for ingress (auto-generated from ingress_domain if empty)"
  type        = string
  default     = ""
}

variable "ingress_class" {
  description = "Ingress class (traefik, nginx)"
  type        = string
  default     = "traefik" # Bates clusters use traefik by default
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
# DNS is managed externally via Bates College DNS infrastructure.
# Ingress hosts are configured via ingress_domain variable.

# =============================================================================
# DNS Configuration (Legacy)
# =============================================================================
# These variables are kept for compatibility with the dns-record module.

variable "dns_provider" {
  description = "DNS provider (external-dns, dreamhost, or none)"
  type        = string
  default     = "external-dns"
}

variable "domain" {
  description = "Base domain for DNS records"
  type        = string
  default     = "beehive.bates.edu"
}

variable "dreamhost_api_key" {
  description = "Dreamhost API key (only required if dns_provider = dreamhost)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "load_balancer_ip" {
  description = "Load balancer IP for DNS records (auto-detected if empty)"
  type        = string
  default     = ""
}

variable "enable_staging_dns" {
  description = "Enable staging DNS record"
  type        = bool
  default     = false
}

# =============================================================================
# MinIO Storage (Optional - High Performance Cache Storage)
# =============================================================================
# MinIO provides self-managed S3-compatible storage optimized for Nix binary
# cache workloads. When enabled, Attic uses MinIO instead of external S3.

variable "use_minio" {
  description = "Deploy MinIO for S3 storage instead of external S3"
  type        = bool
  default     = false
}

variable "install_minio_operator" {
  description = "Install MinIO operator (set to false if already installed)"
  type        = bool
  default     = true
}

variable "minio_operator_create_namespace" {
  description = "Create the MinIO operator namespace (set false if namespace exists)"
  type        = bool
  default     = true
}

variable "minio_operator_namespace" {
  description = "Namespace for MinIO operator"
  type        = string
  default     = "minio-operator"
}

variable "minio_operator_version" {
  description = "MinIO operator Helm chart version"
  type        = string
  default     = "6.0.4"
}

variable "minio_distributed_mode" {
  description = "Use distributed mode (4 servers × 4 drives) for production HA"
  type        = bool
  default     = false
}

variable "minio_volume_size" {
  description = "Storage size for each MinIO volume (per drive)"
  type        = string
  default     = "10Gi"
}

variable "minio_storage_class" {
  description = "Kubernetes storage class for MinIO volumes (uses pg_storage_class if empty)"
  type        = string
  default     = ""
}

variable "minio_cpu_request" {
  description = "CPU request for MinIO pods"
  type        = string
  default     = "100m"
}

variable "minio_cpu_limit" {
  description = "CPU limit for MinIO pods"
  type        = string
  default     = "500m"
}

variable "minio_memory_request" {
  description = "Memory request for MinIO pods"
  type        = string
  default     = "256Mi"
}

variable "minio_memory_limit" {
  description = "Memory limit for MinIO pods"
  type        = string
  default     = "512Mi"
}

variable "minio_root_user" {
  description = "MinIO root username"
  type        = string
  default     = "minioadmin"
  sensitive   = true
}

variable "minio_root_password" {
  description = "MinIO root password (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "minio_bucket_name" {
  description = "MinIO bucket name for Attic storage"
  type        = string
  default     = "attic"
}

variable "minio_nar_retention_days" {
  description = "Retention period for NAR files in days"
  type        = number
  default     = 90
}

variable "minio_chunk_retention_days" {
  description = "Retention period for chunk files in days"
  type        = number
  default     = 90
}

variable "enable_cache_warming" {
  description = "Enable cache warming CronJob for common flake inputs"
  type        = bool
  default     = false
}

# =============================================================================
# Bazel Remote Cache Configuration
# =============================================================================
# Optional bazel-remote cache server for Bazel action caching.
# Uses the same MinIO backend as Attic when use_minio=true.

variable "enable_bazel_cache" {
  description = "Deploy bazel-remote cache server"
  type        = bool
  default     = false
}

variable "bazel_cache_bucket" {
  description = "MinIO/S3 bucket name for Bazel cache"
  type        = string
  default     = "bazel-cache"
}

variable "bazel_cache_max_size_gb" {
  description = "Maximum cache size in GB (for LRU eviction)"
  type        = number
  default     = 100
}

variable "bazel_cache_min_replicas" {
  description = "Minimum number of bazel-cache replicas"
  type        = number
  default     = 1
}

variable "bazel_cache_max_replicas" {
  description = "Maximum number of bazel-cache replicas"
  type        = number
  default     = 2
}

variable "bazel_cache_cpu_request" {
  description = "CPU request for bazel-cache"
  type        = string
  default     = "100m"
}

variable "bazel_cache_memory_request" {
  description = "Memory request for bazel-cache"
  type        = string
  default     = "256Mi"
}

variable "bazel_cache_cpu_limit" {
  description = "CPU limit for bazel-cache"
  type        = string
  default     = "500m"
}

variable "bazel_cache_memory_limit" {
  description = "Memory limit for bazel-cache"
  type        = string
  default     = "1Gi"
}

variable "bazel_cache_enable_ingress" {
  description = "Enable external ingress for bazel-cache"
  type        = bool
  default     = false
}

variable "bazel_cache_ingress_host" {
  description = "Hostname for bazel-cache external ingress"
  type        = string
  default     = ""
}

# =============================================================================
# Token Management (DISABLED)
# =============================================================================
# Token management has been removed for Bates internal network deployment.
# The cache operates in public read/write mode without authentication.
