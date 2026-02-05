# MinIO Tenant Module - Variables
#
# Configuration variables for MinIO tenant deployment.

# =============================================================================
# Required Variables
# =============================================================================

variable "tenant_name" {
  description = "Name of the MinIO tenant"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.tenant_name))
    error_message = "tenant_name must be lowercase alphanumeric with optional hyphens"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for the tenant"
  type        = string
}

variable "credentials_secret" {
  description = "Name of the secret containing MINIO_ROOT_USER and MINIO_ROOT_PASSWORD"
  type        = string
}

# =============================================================================
# Deployment Mode
# =============================================================================

variable "distributed_mode" {
  description = "Use distributed mode (4 servers × 4 drives) for production HA. False = standalone mode (1 server × 1 drive)."
  type        = bool
  default     = false
}

# =============================================================================
# Image Configuration
# =============================================================================

variable "minio_image" {
  description = "MinIO server container image"
  type        = string
  default     = "quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z"
}

# =============================================================================
# Storage Configuration
# =============================================================================

variable "storage_class" {
  description = "Kubernetes storage class for MinIO volumes"
  type        = string
  default     = "trident-expandable-delete"
}

variable "volume_size" {
  description = "Size of each MinIO volume (per drive)"
  type        = string
  default     = "10Gi"
}

# =============================================================================
# Resource Limits
# =============================================================================

variable "cpu_request" {
  description = "CPU request for MinIO pods"
  type        = string
  default     = "100m"
}

variable "cpu_limit" {
  description = "CPU limit for MinIO pods"
  type        = string
  default     = "500m"
}

variable "memory_request" {
  description = "Memory request for MinIO pods"
  type        = string
  default     = "256Mi"
}

variable "memory_limit" {
  description = "Memory limit for MinIO pods"
  type        = string
  default     = "512Mi"
}

# =============================================================================
# Bucket Configuration
# =============================================================================

variable "buckets" {
  description = "List of buckets to create"
  type = list(object({
    name        = string
    object_lock = optional(bool, false)
    region      = optional(string, "us-east-1")
  }))
  default = [
    {
      name = "attic"
    }
  ]
}

# =============================================================================
# User Configuration
# =============================================================================

variable "users" {
  description = "List of MinIO users to create (references secrets)"
  type = list(object({
    name = string
  }))
  default = []
}

# =============================================================================
# Performance Tuning
# =============================================================================

variable "api_requests_max" {
  description = "Maximum concurrent API requests (high for cache workloads)"
  type        = number
  default     = 1000
}

# =============================================================================
# Features
# =============================================================================

variable "enable_console" {
  description = "Enable MinIO Console (web UI)"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable Prometheus monitoring via ServiceMonitor"
  type        = bool
  default     = true
}

variable "request_auto_cert" {
  description = "Request auto-generated TLS certificate from cert-manager"
  type        = bool
  default     = false
}

# =============================================================================
# Lifecycle Configuration (for ILM policies)
# =============================================================================

variable "enable_lifecycle_policies" {
  description = "Enable bucket lifecycle policies for NAR/chunk expiration"
  type        = bool
  default     = true
}

variable "nar_retention_days" {
  description = "Retention period for NAR files (days)"
  type        = number
  default     = 90
}

variable "chunk_retention_days" {
  description = "Retention period for chunk files (days)"
  type        = number
  default     = 90
}

variable "abort_incomplete_days" {
  description = "Days after which to abort incomplete multipart uploads"
  type        = number
  default     = 1
}

# =============================================================================
# Labels & Annotations
# =============================================================================

variable "additional_labels" {
  description = "Additional labels to apply to MinIO resources"
  type        = map(string)
  default     = {}
}
