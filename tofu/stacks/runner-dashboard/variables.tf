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

# =============================================================================
# Container Registry Authentication
# =============================================================================

variable "image_pull_secret_name" {
  description = "Name of imagePullSecret for private container registry"
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

# =============================================================================
# Caddy Reverse Proxy Sidecar
# =============================================================================

variable "enable_caddy_proxy" {
  description = "Enable Caddy reverse proxy sidecar for mTLS/Tailscale"
  type        = bool
  default     = false
}

variable "caddy_mode" {
  description = "Caddy proxy mode: passthrough, mtls_only, tailscale_only, mtls_and_tailscale"
  type        = string
  default     = "passthrough"
}

variable "caddy_image" {
  description = "Container image for Caddy with Tailscale plugin"
  type        = string
  default     = "ghcr.io/jesssullivan/caddy-tailscale:latest"
}

variable "caddy_port" {
  description = "Port Caddy listens on"
  type        = number
  default     = 8443
}

variable "caddy_mtls_ca_cert" {
  description = "PEM-encoded CA certificate for mTLS client verification"
  type        = string
  sensitive   = true
  default     = ""
}

variable "caddy_mtls_client_auth_mode" {
  description = "mTLS client auth mode"
  type        = string
  default     = "require_and_verify"
}

variable "caddy_tailscale_auth_key" {
  description = "Tailscale auth key (ephemeral, reusable)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "caddy_tailscale_hostname" {
  description = "Tailscale MagicDNS hostname for the dashboard"
  type        = string
  default     = "runner-dashboard"
}

variable "caddy_cpu_request" {
  description = "CPU request for Caddy sidecar"
  type        = string
  default     = "10m"
}

variable "caddy_cpu_limit" {
  description = "CPU limit for Caddy sidecar"
  type        = string
  default     = "100m"
}

variable "caddy_memory_request" {
  description = "Memory request for Caddy sidecar"
  type        = string
  default     = "32Mi"
}

variable "caddy_memory_limit" {
  description = "Memory limit for Caddy sidecar"
  type        = string
  default     = "64Mi"
}

variable "trust_proxy_headers" {
  description = "Trust X-Webauth-* identity headers from Caddy proxy"
  type        = bool
  default     = false
}

# =============================================================================
# WebAuthn / FIDO2 Configuration
# =============================================================================

variable "webauthn_rp_id" {
  description = "WebAuthn Relying Party ID (must match the domain)"
  type        = string
  default     = ""
}

variable "webauthn_rp_name" {
  description = "WebAuthn Relying Party display name"
  type        = string
  default     = "Runner Dashboard"
}

variable "database_url" {
  description = "PostgreSQL connection URL for WebAuthn credential storage"
  type        = string
  sensitive   = true
  default     = ""
}
