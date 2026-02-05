# HPA-Enabled Deployment Module - Variables
#
# Comprehensive variable definitions for the reusable HPA deployment module.

# =============================================================================
# Required Variables
# =============================================================================

variable "name" {
  description = "Name of the deployment/service (e.g., attic, quay, pulp)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "Name must be lowercase alphanumeric with optional hyphens"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "Namespace must be lowercase alphanumeric with optional hyphens"
  }
}

variable "image" {
  description = "Container image (e.g., heywoodlh/attic:latest)"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

# =============================================================================
# Component Identification
# =============================================================================

variable "component" {
  description = "Component type for labeling (e.g., cache, api, worker)"
  type        = string
  default     = "api"
}

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "additional_annotations" {
  description = "Additional annotations for the deployment"
  type        = map(string)
  default     = {}
}

variable "pod_annotations" {
  description = "Additional annotations for pods"
  type        = map(string)
  default     = {}
}

variable "wait_for_rollout" {
  description = "Wait for deployment rollout to complete (set false for async deploys)"
  type        = bool
  default     = true
}

# =============================================================================
# Container Configuration
# =============================================================================

variable "container_args" {
  description = "Arguments to pass to the container"
  type        = list(string)
  default     = []
}

variable "environment_variables" {
  description = "Direct environment variables (non-sensitive)"
  type        = map(string)
  default     = {}
}

variable "env_from_secrets" {
  description = "List of secret names to load as environment variables"
  type        = list(string)
  default     = []
}

variable "env_from_config_maps" {
  description = "List of config map names to load as environment variables"
  type        = list(string)
  default     = []
}

variable "config_map_mounts" {
  description = "Config maps to mount as volumes"
  type = list(object({
    name       = string
    mount_path = string
    config_map = string
    read_only  = optional(bool, true)
  }))
  default = []
}

variable "secret_mounts" {
  description = "Secrets to mount as volumes"
  type = list(object({
    name       = string
    mount_path = string
    secret     = string
    read_only  = optional(bool, true)
  }))
  default = []
}

# =============================================================================
# Resource Limits
# =============================================================================

variable "cpu_request" {
  description = "CPU request for container"
  type        = string
  default     = "50m"
}

variable "cpu_limit" {
  description = "CPU limit for container"
  type        = string
  default     = "1000m"
}

variable "memory_request" {
  description = "Memory request for container"
  type        = string
  default     = "64Mi"
}

variable "memory_limit" {
  description = "Memory limit for container"
  type        = string
  default     = "512Mi"
}

# =============================================================================
# HPA Configuration
# =============================================================================

variable "enable_hpa" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = true
}

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
  description = "Maximum number of replicas"
  type        = number
  default     = 10

  validation {
    condition     = var.max_replicas >= 1
    error_message = "max_replicas must be at least 1"
  }
}

variable "cpu_target_percent" {
  description = "Target CPU utilization percentage for HPA scaling (0 to disable)"
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_target_percent >= 0 && var.cpu_target_percent <= 100
    error_message = "cpu_target_percent must be between 0 and 100"
  }
}

variable "memory_target_percent" {
  description = "Target memory utilization percentage for HPA scaling (0 to disable)"
  type        = number
  default     = 80

  validation {
    condition     = var.memory_target_percent >= 0 && var.memory_target_percent <= 100
    error_message = "memory_target_percent must be between 0 and 100"
  }
}

variable "custom_metrics" {
  description = "Custom metrics for HPA scaling"
  type = list(object({
    name         = string
    target_value = string
  }))
  default = []
}

# HPA Behavior
variable "scale_down_stabilization_seconds" {
  description = "Stabilization window for scale down (seconds)"
  type        = number
  default     = 300
}

variable "scale_down_percent" {
  description = "Max percentage of pods to scale down per period"
  type        = number
  default     = 10
}

variable "scale_down_pods" {
  description = "Max number of pods to scale down per period"
  type        = number
  default     = 2
}

variable "scale_up_stabilization_seconds" {
  description = "Stabilization window for scale up (seconds)"
  type        = number
  default     = 0
}

variable "scale_up_percent" {
  description = "Max percentage of pods to scale up per period"
  type        = number
  default     = 100
}

variable "scale_up_pods" {
  description = "Max number of pods to scale up per period"
  type        = number
  default     = 4
}

# =============================================================================
# Service Configuration
# =============================================================================

variable "service_port" {
  description = "Service port (external)"
  type        = number
  default     = 80
}

variable "service_type" {
  description = "Kubernetes service type"
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be ClusterIP, NodePort, or LoadBalancer"
  }
}

variable "service_annotations" {
  description = "Annotations for the service"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Ingress Configuration
# =============================================================================

variable "enable_ingress" {
  description = "Create Ingress resource"
  type        = bool
  default     = true
}

variable "ingress_host" {
  description = "Hostname for ingress"
  type        = string
  default     = ""
}

variable "ingress_class" {
  description = "Ingress class (e.g., traefik, nginx)"
  type        = string
  default     = "traefik"
}

variable "ingress_path" {
  description = "Ingress path"
  type        = string
  default     = "/"
}

variable "ingress_path_type" {
  description = "Ingress path type"
  type        = string
  default     = "Prefix"
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

variable "ingress_annotations" {
  description = "Additional annotations for ingress"
  type        = map(string)
  default     = {}
}

variable "ingress_proxy_body_size" {
  description = "Maximum request body size for ingress (for large uploads)"
  type        = string
  default     = "1g"
}

# =============================================================================
# Health Checks
# =============================================================================

variable "health_check_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/health"
}

variable "enable_liveness_probe" {
  description = "Enable liveness probe"
  type        = bool
  default     = true
}

variable "liveness_initial_delay" {
  description = "Initial delay for liveness probe (seconds)"
  type        = number
  default     = 10
}

variable "liveness_period" {
  description = "Period between liveness checks (seconds)"
  type        = number
  default     = 30
}

variable "liveness_timeout" {
  description = "Timeout for liveness probe (seconds)"
  type        = number
  default     = 5
}

variable "liveness_failure_threshold" {
  description = "Failure threshold for liveness probe"
  type        = number
  default     = 3
}

variable "enable_readiness_probe" {
  description = "Enable readiness probe"
  type        = bool
  default     = true
}

variable "readiness_initial_delay" {
  description = "Initial delay for readiness probe (seconds)"
  type        = number
  default     = 5
}

variable "readiness_period" {
  description = "Period between readiness checks (seconds)"
  type        = number
  default     = 10
}

variable "readiness_timeout" {
  description = "Timeout for readiness probe (seconds)"
  type        = number
  default     = 5
}

variable "readiness_failure_threshold" {
  description = "Failure threshold for readiness probe"
  type        = number
  default     = 3
}

# =============================================================================
# Metrics / Monitoring
# =============================================================================

variable "enable_prometheus_scrape" {
  description = "Add Prometheus scrape annotations"
  type        = bool
  default     = true
}

variable "metrics_port" {
  description = "Port for Prometheus metrics (if different from container_port)"
  type        = number
  default     = 8080
}

variable "metrics_path" {
  description = "Path for Prometheus metrics"
  type        = string
  default     = "/metrics"
}

# =============================================================================
# Security Context
# =============================================================================

variable "enable_security_context" {
  description = "Enable pod security context"
  type        = bool
  default     = true
}

variable "run_as_user" {
  description = "User ID to run container as"
  type        = number
  default     = 1000
}

variable "run_as_group" {
  description = "Group ID to run container as"
  type        = number
  default     = 1000
}

variable "fs_group" {
  description = "Filesystem group ID"
  type        = number
  default     = 1000
}

variable "service_account_name" {
  description = "Service account name for the pods"
  type        = string
  default     = "default"
}

# =============================================================================
# Scheduling
# =============================================================================

variable "node_selector" {
  description = "Node selector for pod scheduling"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for pod scheduling"
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = optional(string, "")
    effect   = string
  }))
  default = []
}

variable "enable_topology_spread" {
  description = "Enable topology spread constraints for HA"
  type        = bool
  default     = true
}

# =============================================================================
# Pod Disruption Budget
# =============================================================================

variable "enable_pdb" {
  description = "Create PodDisruptionBudget"
  type        = bool
  default     = true
}

variable "pdb_min_available" {
  description = "Minimum available pods during disruption"
  type        = string
  default     = "1"
}

# =============================================================================
# Init Containers
# =============================================================================

variable "init_containers" {
  description = "Init containers to run before the main container (for waiting on dependencies)"
  type = list(object({
    name    = string
    image   = string
    command = list(string)
    args    = optional(list(string), [])
  }))
  default = []
}
