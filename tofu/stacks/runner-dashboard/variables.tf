# Runner Dashboard Stack - Variables

# =============================================================================
# Kubernetes Authentication
# =============================================================================

variable "k8s_config_path" {
  description = "Path to kubeconfig file (empty uses KUBECONFIG env var)"
  type        = string
  default     = ""
}

variable "cluster_context" {
  description = "Kubernetes context for GitLab Agent"
  type        = string
}

# =============================================================================
# Namespace
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for the dashboard"
  type        = string
  default     = "runner-dashboard"
}

# =============================================================================
# Container Image
# =============================================================================

variable "image" {
  description = "Container image for the runner dashboard"
  type        = string
  default     = ""
}

# =============================================================================
# GitLab OAuth Configuration (Sensitive - set via CI/CD variables or env)
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
  description = "OAuth redirect URI"
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
  description = "Secret key for session encryption (auto-generated if empty)"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# Prometheus
# =============================================================================

variable "prometheus_url" {
  description = "Prometheus server URL for metrics queries"
  type        = string
  default     = "http://prometheus.monitoring.svc.cluster.local:9090"
}

# =============================================================================
# Runner Namespace
# =============================================================================

variable "runners_namespace" {
  description = "Namespace where GitLab runners are deployed"
  type        = string
  default     = "gitlab-runners"
}

# =============================================================================
# Deployment Configuration
# =============================================================================

variable "replicas" {
  description = "Number of dashboard replicas"
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

variable "wait_for_rollout" {
  description = "Wait for deployment rollout to complete"
  type        = bool
  default     = true
}

variable "environment_variables" {
  description = "Additional environment variables"
  type        = map(string)
  default     = {}
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
}

variable "ingress_class" {
  description = "Ingress class (e.g., nginx, traefik)"
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
