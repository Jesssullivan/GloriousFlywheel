# Runner Dashboard Module - Variables

# =============================================================================
# Required Variables
# =============================================================================

variable "name" {
  description = "Name of the deployment/service"
  type        = string
  default     = "runner-dashboard"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "Name must be lowercase alphanumeric with optional hyphens"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string
  default     = "runner-dashboard"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "Namespace must be lowercase alphanumeric with optional hyphens"
  }
}

variable "image" {
  description = "Container image for the runner dashboard"
  type        = string
}

# =============================================================================
# Namespace
# =============================================================================

variable "create_namespace" {
  description = "Create the namespace (set false if it already exists)"
  type        = bool
  default     = true
}

# =============================================================================
# GitLab OAuth Configuration (Sensitive)
# =============================================================================

variable "gitlab_oauth_client_id" {
  description = "GitLab OAuth application client ID"
  type        = string
  sensitive   = true
}

variable "gitlab_oauth_client_secret" {
  description = "GitLab OAuth application client secret"
  type        = string
  sensitive   = true
}

variable "gitlab_oauth_redirect_uri" {
  description = "OAuth redirect URI (e.g., https://runner-dashboard.example.com/auth/callback)"
  type        = string
}

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_token" {
  description = "GitLab API token for runner status queries"
  type        = string
  sensitive   = true
}

variable "session_secret" {
  description = "Secret key for session encryption"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# GitLab Project/Group IDs
# =============================================================================

variable "gitlab_group_id" {
  description = "GitLab group ID for runner status queries"
  type        = string
  default     = ""
}

variable "gitlab_project_id" {
  description = "GitLab project ID for GitOps operations"
  type        = string
  default     = ""
}

variable "runner_stack_name" {
  description = "Name of the runner tofu stack (for GitOps tfvars path)"
  type        = string
  default     = "gitlab-runners"
}

variable "default_env" {
  description = "Default environment name for GitOps operations"
  type        = string
  default     = "dev"
}

# =============================================================================
# Prometheus Configuration
# =============================================================================

variable "prometheus_url" {
  description = "Prometheus server URL for metrics queries"
  type        = string
  default     = "http://prometheus.monitoring.svc.cluster.local:9090"
}

# =============================================================================
# Kubernetes Access
# =============================================================================

variable "runners_namespace" {
  description = "Namespace where GitLab runners are deployed (for RBAC read access)"
  type        = string
  default     = "gitlab-runners"
}

# =============================================================================
# Container Configuration
# =============================================================================

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "replicas" {
  description = "Number of deployment replicas"
  type        = number
  default     = 1
}

variable "node_env" {
  description = "Node environment (production, development)"
  type        = string
  default     = "production"
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "info"
}

variable "environment_variables" {
  description = "Additional environment variables (non-sensitive)"
  type        = map(string)
  default     = {}
}

variable "wait_for_rollout" {
  description = "Wait for deployment rollout to complete"
  type        = bool
  default     = true
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
  default     = "500m"
}

variable "memory_request" {
  description = "Memory request for container"
  type        = string
  default     = "64Mi"
}

variable "memory_limit" {
  description = "Memory limit for container"
  type        = string
  default     = "256Mi"
}

# =============================================================================
# Health Check
# =============================================================================

variable "health_check_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/api/health"
}

# =============================================================================
# Service Configuration
# =============================================================================

variable "service_port" {
  description = "Service port (external)"
  type        = number
  default     = 80
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
  default     = "nginx"
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

# =============================================================================
# Monitoring
# =============================================================================

variable "enable_prometheus_scrape" {
  description = "Add Prometheus scrape annotations to pods"
  type        = bool
  default     = true
}

# =============================================================================
# Labels & Annotations
# =============================================================================

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Scheduling
# =============================================================================

variable "node_selector" {
  description = "Node selector for pod scheduling"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Container Registry Authentication
# =============================================================================

variable "image_pull_secret_name" {
  description = "Name of imagePullSecret for private container registry (auto-created when ghcr_token is set)"
  type        = string
  default     = ""
}

variable "ghcr_token" {
  description = "GitHub PAT with read:packages scope for GHCR pull"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ghcr_username" {
  description = "GitHub username for GHCR auth"
  type        = string
  default     = ""
}

# =============================================================================
# Runtime Environment Configuration
# =============================================================================

variable "environments_config" {
  description = "JSON content for environments.json ConfigMap (empty = use build-time default)"
  type        = string
  default     = ""
}
