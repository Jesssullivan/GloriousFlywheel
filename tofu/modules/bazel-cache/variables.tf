# bazel-cache Module - Variables

# =============================================================================
# Required Variables
# =============================================================================

variable "name" {
  description = "Name of the bazel-remote deployment"
  type        = string
  default     = "bazel-cache"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "Name must be lowercase alphanumeric with optional hyphens"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string
}

# =============================================================================
# S3/MinIO Configuration
# =============================================================================

variable "s3_endpoint" {
  description = "S3/MinIO endpoint (e.g., minio.attic-cache.svc.cluster.local:9000)"
  type        = string
}

variable "s3_bucket" {
  description = "S3/MinIO bucket name for cache storage"
  type        = string
  default     = "bazel-cache"
}

variable "s3_secret" {
  description = "Kubernetes secret name containing access-key and secret-key"
  type        = string
}

variable "s3_prefix" {
  description = "Object prefix within the bucket"
  type        = string
  default     = ""
}

variable "s3_disable_ssl" {
  description = "Disable SSL for S3/MinIO (true for internal MinIO)"
  type        = bool
  default     = true
}

variable "s3_bucket_lookup_type" {
  description = "S3 bucket lookup type: auto, dns, or path"
  type        = string
  default     = "path"

  validation {
    condition     = contains(["auto", "dns", "path"], var.s3_bucket_lookup_type)
    error_message = "s3_bucket_lookup_type must be auto, dns, or path"
  }
}

variable "s3_max_idle_conns" {
  description = "Maximum idle connections to S3"
  type        = number
  default     = 1024
}

variable "s3_update_timestamps" {
  description = "Update object timestamps on cache hit"
  type        = bool
  default     = true
}

# =============================================================================
# Cache Configuration
# =============================================================================

variable "max_cache_size_gb" {
  description = "Maximum cache size in GB (for S3 LRU eviction)"
  type        = number
  default     = 100
}

variable "local_cache_size_gb" {
  description = "Local disk cache size in GB (ephemeral, for faster reads)"
  type        = number
  default     = 10
}

variable "num_uploaders" {
  description = "Number of parallel S3 upload goroutines"
  type        = number
  default     = 100
}

variable "max_queued_uploads" {
  description = "Maximum queued uploads before blocking"
  type        = number
  default     = 1000000
}

# =============================================================================
# Container Configuration
# =============================================================================

variable "image" {
  description = "bazel-remote container image"
  type        = string
  default     = "buchgr/bazel-remote-cache:v2.4.4"
}

variable "cpu_request" {
  description = "CPU request per replica"
  type        = string
  default     = "250m"
}

variable "cpu_limit" {
  description = "CPU limit per replica"
  type        = string
  default     = "1000m"
}

variable "memory_request" {
  description = "Memory request per replica"
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "Memory limit per replica"
  type        = string
  default     = "2Gi"
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
  default     = "default"
}

variable "wait_for_rollout" {
  description = "Wait for deployment rollout to complete"
  type        = bool
  default     = false
}

# =============================================================================
# Scaling Configuration
# =============================================================================

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.min_replicas >= 1
    error_message = "min_replicas must be at least 1"
  }
}

variable "max_replicas" {
  description = "Maximum number of replicas for HPA"
  type        = number
  default     = 4

  validation {
    condition     = var.max_replicas >= 1
    error_message = "max_replicas must be at least 1"
  }
}

variable "cpu_target_percent" {
  description = "Target CPU utilization for HPA"
  type        = number
  default     = 70
}

variable "memory_target_percent" {
  description = "Target memory utilization for HPA"
  type        = number
  default     = 80
}

# =============================================================================
# Ingress Configuration
# =============================================================================

variable "enable_ingress" {
  description = "Create Ingress for external access"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname for Ingress"
  type        = string
  default     = ""
}

variable "ingress_class" {
  description = "Ingress class (nginx, traefik)"
  type        = string
  default     = "nginx"
}

variable "cert_manager_issuer" {
  description = "cert-manager ClusterIssuer name"
  type        = string
  default     = "letsencrypt-prod"
}

variable "ingress_annotations" {
  description = "Additional Ingress annotations"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "enable_metrics" {
  description = "Enable Prometheus metrics endpoint"
  type        = bool
  default     = true
}

variable "access_log_level" {
  description = "Access log level: none or all"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "all"], var.access_log_level)
    error_message = "access_log_level must be none or all"
  }
}

variable "create_service_monitor" {
  description = "Create ServiceMonitor for Prometheus Operator"
  type        = bool
  default     = true
}

variable "prometheus_release_label" {
  description = "Label value for Prometheus selector"
  type        = string
  default     = "prometheus"
}

# =============================================================================
# Labels
# =============================================================================

variable "additional_labels" {
  description = "Additional labels for all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Init Containers
# =============================================================================

variable "init_containers" {
  description = "Init containers to run before the main container"
  type = list(object({
    name    = string
    image   = string
    command = list(string)
    args    = optional(list(string), [])
  }))
  default = []
}
