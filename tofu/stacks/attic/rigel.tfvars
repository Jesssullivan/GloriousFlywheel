# Rigel Cluster Configuration (Staging/Production)
#
# Bates ILS rigel cluster for staging and production deployments.
# Uses GitLab Kubernetes Agent for authentication.

# =============================================================================
# Cluster & Environment
# =============================================================================

environment     = "production"
namespace       = "attic-cache"
cluster_context = "bates-ils/projects/kubernetes/gitlab-agents:rigel"
ingress_domain  = "rigel.bates.edu"

# =============================================================================
# Resource Configuration (Production-ready)
# =============================================================================

# API Server
api_cpu_request    = "100m"
api_memory_request = "128Mi"
api_cpu_limit      = "1000m"
api_memory_limit   = "1Gi"

# HPA Configuration (HA for production)
api_min_replicas = 2
api_max_replicas = 5

# GC Worker
gc_cpu_request    = "50m"
gc_memory_request = "64Mi"
gc_cpu_limit      = "500m"
gc_memory_limit   = "256Mi"

# =============================================================================
# PostgreSQL Configuration (HA for production)
# =============================================================================

use_cnpg_postgres     = true
install_cnpg_operator = true
pg_instances          = 3 # HA cluster
pg_storage_size       = "20Gi"
pg_storage_class      = "trident-expandable-delete" # Bates NetApp Trident CSI (default)

pg_cpu_request    = "250m"
pg_memory_request = "512Mi"
pg_cpu_limit      = "1000m"
pg_memory_limit   = "1Gi"

pg_enable_backup    = true
pg_backup_schedule  = "0 2 * * *" # Daily at 2 AM
pg_backup_retention = "30d"

# =============================================================================
# Ingress Configuration
# =============================================================================

enable_ingress      = true
ingress_host        = "attic-cache.rigel.bates.edu"
ingress_class       = "nginx"
enable_tls          = true
cert_manager_issuer = "letsencrypt-prod"

# =============================================================================
# DNS Configuration
# =============================================================================

dns_provider = "external-dns"
domain       = "rigel.bates.edu"

# =============================================================================
# S3 Storage (Configure these in GitLab CI/CD variables)
# =============================================================================
# s3_endpoint         = "https://s3.example.com"
# s3_region           = "us-east-1"
# s3_bucket_name      = "attic-cache-prod"
# s3_access_key_id    = (set via CI/CD variable)
# s3_secret_access_key = (set via CI/CD variable)

# =============================================================================
# Monitoring
# =============================================================================
# NOTE: Disabled until Prometheus Operator is installed on rigel cluster
# ServiceMonitor CRD requires: monitoring.coreos.com/v1

enable_prometheus_monitoring = false

# =============================================================================
# MinIO Configuration (Distributed for production HA)
# =============================================================================
# When use_minio=true, MinIO provides self-managed S3-compatible storage.
# Distributed mode uses 4 servers × 4 drives = 16 drives total with erasure coding.

use_minio              = true
minio_distributed_mode = true   # 4x4 distributed for HA
minio_volume_size      = "50Gi" # Per volume (16 total = 800Gi raw)
minio_storage_class    = "trident-expandable-delete"

# Production resources
minio_cpu_request    = "500m"
minio_memory_request = "1Gi"
minio_cpu_limit      = "2000m"
minio_memory_limit   = "4Gi"

minio_bucket_name          = "attic"
minio_nar_retention_days   = 90 # 3 months retention for production
minio_chunk_retention_days = 90

# Enable cache warming for production
enable_cache_warming = true
