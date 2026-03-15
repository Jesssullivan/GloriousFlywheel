# ARC Runners Stack - Variables

# =============================================================================
# Kubernetes Authentication
# =============================================================================

variable "k8s_config_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "cluster_context" {
  description = "Kubernetes context"
  type        = string
}

# =============================================================================
# GitHub Configuration
# =============================================================================

variable "github_config_url" {
  description = "GitHub organization or repository URL for runner registration"
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/.+", var.github_config_url))
    error_message = "github_config_url must be a GitHub URL (e.g. https://github.com/my-org)"
  }
}

variable "github_config_secret" {
  description = "Name of K8s secret containing GitHub App credentials (in arc-systems namespace)"
  type        = string
  default     = "github-app-secret"
}

# =============================================================================
# Namespace Configuration
# =============================================================================

variable "controller_namespace" {
  description = "Namespace for ARC controller"
  type        = string
  default     = "arc-systems"
}

variable "create_controller_namespace" {
  description = "Create the controller namespace"
  type        = bool
  default     = true
}

variable "runner_namespace" {
  description = "Namespace for runner scale sets"
  type        = string
  default     = "arc-runners"
}

variable "create_runner_namespace" {
  description = "Create the runner namespace"
  type        = bool
  default     = true
}

# =============================================================================
# Controller Configuration
# =============================================================================

variable "controller_chart_version" {
  description = "ARC controller Helm chart version"
  type        = string
  default     = "0.13.1"
}

# =============================================================================
# Runner Names
# =============================================================================

variable "nix_runner_name" {
  description = "Helm release name for Nix runner scale set"
  type        = string
  default     = "gh-nix"
}

variable "docker_runner_name" {
  description = "Helm release name for Docker runner scale set"
  type        = string
  default     = "gh-docker"
}

variable "dind_runner_name" {
  description = "Helm release name for DinD runner scale set"
  type        = string
  default     = "gh-dind"
}

# =============================================================================
# Deploy Toggles
# =============================================================================

variable "deploy_docker_runner" {
  description = "Deploy the Docker runner scale set"
  type        = bool
  default     = true
}

variable "deploy_dind_runner" {
  description = "Deploy the DinD runner scale set"
  type        = bool
  default     = false
}

# =============================================================================
# Nix Runner Configuration
# =============================================================================

variable "nix_min_runners" {
  description = "Minimum Nix runner pods (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "nix_max_runners" {
  description = "Maximum Nix runner pods"
  type        = number
  default     = 5
}

variable "nix_cpu_request" {
  type    = string
  default = "500m"
}

variable "nix_memory_request" {
  type    = string
  default = "1Gi"
}

variable "nix_cpu_limit" {
  type    = string
  default = "4"
}

variable "nix_memory_limit" {
  type    = string
  default = "8Gi"
}

# =============================================================================
# Docker Runner Configuration
# =============================================================================

variable "docker_min_runners" {
  description = "Minimum Docker runner pods"
  type        = number
  default     = 0
}

variable "docker_max_runners" {
  description = "Maximum Docker runner pods"
  type        = number
  default     = 5
}

variable "docker_cpu_request" {
  type    = string
  default = "100m"
}

variable "docker_memory_request" {
  type    = string
  default = "256Mi"
}

variable "docker_cpu_limit" {
  type    = string
  default = "2"
}

variable "docker_memory_limit" {
  type    = string
  default = "4Gi"
}

# =============================================================================
# DinD Runner Configuration
# =============================================================================

variable "dind_min_runners" {
  description = "Minimum DinD runner pods"
  type        = number
  default     = 0
}

variable "dind_max_runners" {
  description = "Maximum DinD runner pods"
  type        = number
  default     = 5
}

variable "dind_cpu_request" {
  type    = string
  default = "500m"
}

variable "dind_memory_request" {
  type    = string
  default = "1Gi"
}

variable "dind_cpu_limit" {
  type    = string
  default = "4"
}

variable "dind_memory_limit" {
  type    = string
  default = "8Gi"
}

# =============================================================================
# Cache Integration
# =============================================================================

variable "attic_server" {
  description = "Attic cache server URL for Nix runners"
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
# GHCR Registry Authentication
# =============================================================================

variable "ghcr_token" {
  description = "GHCR personal access token for pulling mirrored images (empty to skip)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ghcr_username" {
  description = "GHCR username for image pull authentication"
  type        = string
  default     = ""
}

# =============================================================================
# Extra Runner Scale Sets (multi-org / cross-repo)
# =============================================================================

variable "extra_runner_sets" {
  description = "Additional runner scale sets for external repos/orgs (keyed by unique name)"
  type = map(object({
    github_config_url    = string
    github_config_secret = optional(string, "github-app-secret")
    runner_label         = string
    runner_type          = optional(string, "nix")
    container_mode       = optional(string, "")
    runner_image         = optional(string, "")
    min_runners          = optional(number, 0)
    max_runners          = optional(number, 5)
    cpu_request          = optional(string, "500m")
    memory_request       = optional(string, "1Gi")
    cpu_limit            = optional(string, "4")
    memory_limit         = optional(string, "8Gi")
    attic_server         = optional(string, "")
    attic_cache          = optional(string, "main")
    bazel_cache_endpoint = optional(string, "")
  }))
  default = {}
}
