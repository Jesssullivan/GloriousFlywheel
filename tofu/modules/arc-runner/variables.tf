# ARC Runner Module - Variables
#
# Variables for deploying a GitHub Actions runner scale set via ARC.

# =============================================================================
# Runner Identity
# =============================================================================

variable "runner_name" {
  description = "Helm release name for the runner scale set (e.g. gh-nix)"
  type        = string
}

variable "runner_label" {
  description = "The runs-on label for GitHub Actions workflows (e.g. tinyland-nix)"
  type        = string
}

variable "runner_type" {
  description = "Type of runner: docker, dind, nix"
  type        = string
  default     = "docker"

  validation {
    condition     = contains(["docker", "dind", "nix"], var.runner_type)
    error_message = "runner_type must be one of: docker, dind, nix"
  }
}

# =============================================================================
# GitHub Configuration
# =============================================================================

variable "github_config_url" {
  description = "GitHub organization or repository URL for runner registration"
  type        = string
}

variable "github_config_secret" {
  description = "Name of K8s secret containing GitHub App credentials"
  type        = string
}

variable "runner_group" {
  description = "GitHub runner group name"
  type        = string
  default     = "default"
}

# =============================================================================
# Namespace Configuration
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for runner scale set"
  type        = string
  default     = "arc-runners"
}

variable "controller_namespace" {
  description = "Namespace where ARC controller is deployed (for secret reference)"
  type        = string
  default     = "arc-systems"
}

variable "controller_service_account_name" {
  description = "Service account name of the ARC controller (required when multiple controllers exist)"
  type        = string
  default     = "arc-controller-gha-rs-controller"
}

# =============================================================================
# Helm Configuration
# =============================================================================

variable "chart_version" {
  description = "ARC runner scale set Helm chart version"
  type        = string
  default     = "0.13.1"
}

# =============================================================================
# Autoscaling
# =============================================================================

variable "min_runners" {
  description = "Minimum number of runner pods (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "max_runners" {
  description = "Maximum number of runner pods"
  type        = number
  default     = 5
}

# =============================================================================
# Container Configuration
# =============================================================================

variable "container_mode" {
  description = "Container mode: kubernetes or dind (auto-detected from runner_type if empty)"
  type        = string
  default     = ""

  validation {
    condition     = var.container_mode == "" || contains(["kubernetes", "dind"], var.container_mode)
    error_message = "container_mode must be empty (auto), kubernetes, or dind"
  }
}

# =============================================================================
# Resource Requests and Limits
# =============================================================================

variable "cpu_request" {
  description = "CPU request for runner pods"
  type        = string
  default     = "250m"
}

variable "memory_request" {
  description = "Memory request for runner pods"
  type        = string
  default     = "512Mi"
}

variable "cpu_limit" {
  description = "CPU limit for runner pods"
  type        = string
  default     = "2"
}

variable "memory_limit" {
  description = "Memory limit for runner pods"
  type        = string
  default     = "4Gi"
}

# =============================================================================
# Cache Integration
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

variable "bazel_cache_endpoint" {
  description = "Bazel remote cache gRPC endpoint"
  type        = string
  default     = ""
}

# =============================================================================
# Image Configuration
# =============================================================================

variable "runner_image" {
  description = "Override runner container image (default: auto from runner_type)"
  type        = string
  default     = ""
}

variable "image_pull_secrets" {
  description = "Image pull secrets for runner pods"
  type        = list(string)
  default     = []
}

# =============================================================================
# Pod Scheduling
# =============================================================================

variable "node_selector" {
  description = "Node selector for runner pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for runner pods"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

# =============================================================================
# Additional Environment Variables
# =============================================================================

variable "env_vars" {
  description = "Additional environment variables for runner pods"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
