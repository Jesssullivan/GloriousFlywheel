# GitLab Runner Module - Variables
#
# Enhanced variables supporting multiple runner types, HPA, and group registration.

# =============================================================================
# GitLab Configuration
# =============================================================================

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "runner_token" {
  description = "Runner authentication token (from GitLab UI or API)"
  type        = string
  sensitive   = true
}

variable "runner_name" {
  description = "Name for the runner Helm release"
  type        = string
}

variable "runner_tags" {
  description = "Tags for the runner"
  type        = list(string)
  default     = []
}

# =============================================================================
# Runner Type Configuration
# =============================================================================

variable "runner_type" {
  description = "Type of runner: docker, dind, rocky8, rocky9, nix"
  type        = string
  default     = "docker"

  validation {
    condition     = contains(["docker", "dind", "rocky8", "rocky9", "nix"], var.runner_type)
    error_message = "runner_type must be one of: docker, dind, rocky8, rocky9, nix"
  }
}

variable "default_image" {
  description = "Default container image for jobs (overrides runner_type default)"
  type        = string
  default     = ""
}

# =============================================================================
# Namespace Configuration
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for runner"
  type        = string
  default     = "gitlab-runners"
}

variable "create_namespace" {
  description = "Create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

# =============================================================================
# Runner Behavior
# =============================================================================

variable "chart_version" {
  description = "GitLab Runner Helm chart version"
  type        = string
  default     = "0.71.0"
}

variable "privileged" {
  description = "Run containers in privileged mode (required for DinD)"
  type        = bool
  default     = null # Auto-set based on runner_type if not specified
}

variable "concurrent_jobs" {
  description = "Maximum concurrent jobs per runner manager pod"
  type        = number
  default     = 4
}

variable "run_untagged" {
  description = "Allow runner to pick up untagged jobs"
  type        = bool
  default     = false
}

variable "protected" {
  description = "Only run jobs on protected branches"
  type        = bool
  default     = false
}

# =============================================================================
# Resource Requests and Limits (Manager Pod)
# =============================================================================

variable "cpu_request" {
  description = "CPU request for runner manager pod"
  type        = string
  default     = "100m"
}

variable "memory_request" {
  description = "Memory request for runner manager pod"
  type        = string
  default     = "128Mi"
}

variable "cpu_limit" {
  description = "CPU limit for runner manager pod"
  type        = string
  default     = "500m"
}

variable "memory_limit" {
  description = "Memory limit for runner manager pod"
  type        = string
  default     = "512Mi"
}

# =============================================================================
# Job Pod Resources
# =============================================================================

variable "job_cpu_request" {
  description = "CPU request for job pods"
  type        = string
  default     = "100m"
}

variable "job_memory_request" {
  description = "Memory request for job pods"
  type        = string
  default     = "256Mi"
}

variable "job_cpu_limit" {
  description = "CPU limit for job pods"
  type        = string
  default     = "2"
}

variable "job_memory_limit" {
  description = "Memory limit for job pods"
  type        = string
  default     = "2Gi"
}

# =============================================================================
# RBAC Configuration
# =============================================================================

variable "rbac_create" {
  description = "Create RBAC resources"
  type        = bool
  default     = true
}

variable "cluster_wide_access" {
  description = "Allow cluster-wide access (for deploying to any namespace)"
  type        = bool
  default     = false
}

variable "service_account_name" {
  description = "Service account name for runner"
  type        = string
  default     = ""
}

# =============================================================================
# DinD Configuration (for dind runner type)
# =============================================================================

variable "dind_enabled" {
  description = "Enable Docker-in-Docker service container"
  type        = bool
  default     = null # Auto-set based on runner_type
}

variable "docker_version" {
  description = "Docker version for DinD service"
  type        = string
  default     = "27-dind"
}

# =============================================================================
# Nix/Attic Configuration (for nix runner type)
# =============================================================================

variable "attic_server" {
  description = "Attic cache server URL"
  type        = string
  default     = ""
}

variable "attic_cache" {
  description = "Attic cache name"
  type        = string
  default     = "main"
}

variable "attic_token" {
  description = "Attic authentication token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "nix_store_size" {
  description = "Size limit for Nix store emptyDir volume"
  type        = string
  default     = "20Gi"
}

# =============================================================================
# HPA Configuration
# =============================================================================

variable "hpa_enabled" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = false
}

variable "hpa_min_replicas" {
  description = "Minimum number of runner manager replicas"
  type        = number
  default     = 1
}

variable "hpa_max_replicas" {
  description = "Maximum number of runner manager replicas"
  type        = number
  default     = 5
}

variable "hpa_cpu_target" {
  description = "Target CPU utilization percentage for HPA"
  type        = number
  default     = 70
}

variable "hpa_memory_target" {
  description = "Target memory utilization percentage for HPA"
  type        = number
  default     = 80
}

variable "hpa_scale_up_window" {
  description = "Stabilization window for scaling up (seconds)"
  type        = number
  default     = 15
}

variable "hpa_scale_down_window" {
  description = "Stabilization window for scaling down (seconds)"
  type        = number
  default     = 300
}

# =============================================================================
# Pod Disruption Budget
# =============================================================================

variable "pdb_enabled" {
  description = "Enable Pod Disruption Budget"
  type        = bool
  default     = false
}

variable "pdb_min_available" {
  description = "Minimum number of pods that must be available"
  type        = number
  default     = 1
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "metrics_enabled" {
  description = "Enable Prometheus metrics endpoint"
  type        = bool
  default     = true
}

variable "service_monitor_enabled" {
  description = "Create Prometheus ServiceMonitor resource"
  type        = bool
  default     = false
}

variable "service_monitor_labels" {
  description = "Labels for ServiceMonitor resource"
  type        = map(string)
  default     = {}
}

variable "metric_prefix" {
  description = "Prefix for Prometheus recording rule metric names"
  type        = string
  default     = "org"
}

variable "enrollment_alerts_enabled" {
  description = "Enable enrollment-specific alerts (quota exhaustion, namespace leak, queue backlog)"
  type        = bool
  default     = false
}

# =============================================================================
# Cache Integration
# =============================================================================

variable "bazel_cache_endpoint" {
  description = "Bazel remote cache gRPC endpoint (injected as env var into job pods)"
  type        = string
  default     = ""
}

# =============================================================================
# Additional Configuration
# =============================================================================

variable "additional_values" {
  description = "Additional Helm values in YAML format"
  type        = string
  default     = ""
}

variable "node_selector" {
  description = "Node selector for runner manager pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for runner manager pods"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

variable "pod_labels" {
  description = "Additional labels for runner manager pods"
  type        = map(string)
  default     = {}
}

variable "pod_annotations" {
  description = "Additional annotations for runner manager pods"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Namespace Per Job (Untrusted Isolation)
# =============================================================================

variable "namespace_per_job" {
  description = "Create a unique namespace per CI job for isolation"
  type        = bool
  default     = false
}

variable "namespace_per_job_prefix" {
  description = "Prefix for per-job namespaces"
  type        = string
  default     = "ci-job-"
}

# =============================================================================
# Cleanup Configuration
# =============================================================================

variable "cleanup_enabled" {
  description = "Enable automatic cleanup of completed job pods"
  type        = bool
  default     = true
}

variable "cleanup_grace_seconds" {
  description = "Grace period before deleting completed pods"
  type        = number
  default     = 3600
}
