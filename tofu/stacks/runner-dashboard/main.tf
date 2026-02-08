# Runner Dashboard Stack
#
# Deploys the GitLab Runner Dashboard to Kubernetes clusters.
# Provides real-time monitoring of GitLab runners with OAuth.
#
# Usage:
#   cd tofu/stacks/runner-dashboard
#   tofu init
#   tofu plan -var-file=beehive.tfvars
#   tofu apply -var-file=beehive.tfvars

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# =============================================================================
# Kubernetes Provider Configuration (GitLab Kubernetes Agent)
# =============================================================================

provider "kubernetes" {
  config_path    = var.k8s_config_path != "" ? var.k8s_config_path : null
  config_context = var.cluster_context
}

# =============================================================================
# Runner Dashboard Module
# =============================================================================

module "runner_dashboard" {
  source = "../../modules/runner-dashboard"

  name             = "runner-dashboard"
  namespace        = var.namespace
  create_namespace = true
  image            = var.image

  # GitLab OAuth
  gitlab_oauth_client_id     = var.gitlab_oauth_client_id
  gitlab_oauth_client_secret = var.gitlab_oauth_client_secret
  gitlab_oauth_redirect_uri  = var.gitlab_oauth_redirect_uri
  gitlab_url                 = var.gitlab_url
  gitlab_token               = var.gitlab_token
  session_secret             = var.session_secret

  # Prometheus
  prometheus_url = var.prometheus_url

  # Kubernetes access
  runners_namespace = var.runners_namespace

  # Container settings
  container_port = 3000
  replicas       = var.replicas
  node_env       = var.node_env
  log_level      = var.log_level

  # Resources
  cpu_request    = var.cpu_request
  cpu_limit      = var.cpu_limit
  memory_request = var.memory_request
  memory_limit   = var.memory_limit

  # Ingress
  enable_ingress      = var.enable_ingress
  ingress_host        = var.ingress_host
  ingress_class       = var.ingress_class
  enable_tls          = var.enable_tls
  cert_manager_issuer = var.cert_manager_issuer
  ingress_annotations = var.ingress_annotations

  # Monitoring
  enable_prometheus_scrape = var.enable_prometheus_scrape

  # Deployment behavior
  wait_for_rollout = var.wait_for_rollout

  # Additional env vars
  environment_variables = var.environment_variables
}

# =============================================================================
# Outputs
# =============================================================================

output "namespace" {
  description = "Kubernetes namespace for runner dashboard"
  value       = module.runner_dashboard.deployment_namespace
}

output "deployment_name" {
  description = "Name of the dashboard deployment"
  value       = module.runner_dashboard.deployment_name
}

output "service_endpoint" {
  description = "Internal service endpoint"
  value       = module.runner_dashboard.service_endpoint
}

output "ingress_url" {
  description = "External URL for the dashboard (if ingress enabled)"
  value       = module.runner_dashboard.ingress_url
}

output "service_account" {
  description = "Service account name"
  value       = module.runner_dashboard.service_account_name
}

output "resource_config" {
  description = "Resource requests and limits"
  value       = module.runner_dashboard.resource_config
}
