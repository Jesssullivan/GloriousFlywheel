# Beehive Cluster Configuration (Dev/Review)
#
# Bates ILS beehive cluster for development and merge request reviews.
# Uses GitLab Kubernetes Agent for authentication.

# =============================================================================
# Cluster & Environment
# =============================================================================

environment     = "development"
namespace       = "attic-cache-dev"
cluster_context = "bates-ils/projects/kubernetes/gitlab-agents:beehive"
ingress_domain  = "beehive.bates.edu"

# =============================================================================
# Resource Configuration (Minimal for dev)
# =============================================================================

# API Server
api_cpu_request    = "50m"
api_memory_request = "64Mi"
api_cpu_limit      = "500m"
api_memory_limit   = "512Mi"

# HPA Configuration (minimal replicas for dev)
api_min_replicas = 1
api_max_replicas = 2

# GC Worker
gc_cpu_request    = "25m"
gc_memory_request = "32Mi"
gc_cpu_limit      = "250m"
gc_memory_limit   = "128Mi"

# =============================================================================
# PostgreSQL Configuration (Minimal for dev)
# =============================================================================

use_cnpg_postgres     = true
install_cnpg_operator = true
pg_instances          = 1 # Single instance for dev
pg_storage_size       = "5Gi"
pg_storage_class      = "trident-delete" # Bates uses NetApp Trident CSI

pg_cpu_request    = "100m"
pg_memory_request = "256Mi"
pg_cpu_limit      = "500m"
pg_memory_limit   = "512Mi"

pg_enable_backup = false # Disable backups for dev

# =============================================================================
# Ingress Configuration
# =============================================================================

enable_ingress      = true
ingress_host        = "attic-cache.beehive.bates.edu"
ingress_class       = "nginx"
enable_tls          = true
cert_manager_issuer = "letsencrypt-prod"

# =============================================================================
# DNS Configuration
# =============================================================================

dns_provider = "external-dns"
domain       = "beehive.bates.edu"

# =============================================================================
# S3 Storage (Configure these in GitLab CI/CD variables)
# =============================================================================
# s3_endpoint         = "https://s3.example.com"
# s3_region           = "us-east-1"
# s3_bucket_name      = "attic-cache-dev"
# s3_access_key_id    = (set via CI/CD variable)
# s3_secret_access_key = (set via CI/CD variable)

# =============================================================================
# Monitoring
# =============================================================================

enable_prometheus_monitoring = false # Disable for dev to reduce resource usage

# =============================================================================
# MinIO Configuration (Standalone for dev)
# =============================================================================
# When use_minio=true, MinIO provides self-managed S3-compatible storage.
# Standalone mode uses a single server with minimal resources.
#
# NOTE: install_minio_operator=false because the MinIO Operator is already
# installed cluster-wide on beehive from another project.

use_minio              = true
install_minio_operator = false  # Use existing operator on beehive
minio_distributed_mode = false # Single server for dev
minio_volume_size      = "10Gi"
minio_storage_class    = "trident-delete"

# Minimal resources for development
minio_cpu_request    = "100m"
minio_memory_request = "256Mi"
minio_cpu_limit      = "500m"
minio_memory_limit   = "512Mi"

minio_bucket_name          = "attic"
minio_nar_retention_days   = 30 # Shorter retention for dev
minio_chunk_retention_days = 30

# Cache warming disabled for dev
enable_cache_warming = false
