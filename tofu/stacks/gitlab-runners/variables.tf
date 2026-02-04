# GitLab Runners Stack - Variables

# =============================================================================
# Kubernetes Authentication
# =============================================================================

variable "k8s_config_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "cluster_context" {
  description = "Kubernetes context for GitLab Agent"
  type        = string
}

# =============================================================================
# GitLab Configuration
# =============================================================================

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "nix_runner_token" {
  description = "Runner token for Nix runner (create in GitLab > Settings > CI/CD > Runners)"
  type        = string
  sensitive   = true
}

variable "k8s_runner_token" {
  description = "Runner token for K8s runner (create in GitLab > Settings > CI/CD > Runners)"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# Namespace
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for runners"
  type        = string
  default     = "gitlab-runners"
}

variable "create_namespace" {
  description = "Create the namespace"
  type        = bool
  default     = true
}

# =============================================================================
# Runner Configuration
# =============================================================================

variable "deploy_k8s_runner" {
  description = "Deploy the K8s/tofu runner"
  type        = bool
  default     = true
}

variable "nix_concurrent_jobs" {
  description = "Max concurrent Nix build jobs"
  type        = number
  default     = 4
}

variable "k8s_concurrent_jobs" {
  description = "Max concurrent K8s deploy jobs"
  type        = number
  default     = 4
}

variable "nix_cpu_request" {
  description = "CPU request for Nix runner manager"
  type        = string
  default     = "100m"
}

variable "nix_memory_request" {
  description = "Memory request for Nix runner manager"
  type        = string
  default     = "128Mi"
}
