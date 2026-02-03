# HPA-Enabled Deployment Module - Outputs
#
# Outputs for integration with other modules and CI/CD pipelines.

# =============================================================================
# Deployment Outputs
# =============================================================================

output "deployment_name" {
  description = "Name of the Kubernetes deployment"
  value       = kubernetes_deployment.main.metadata[0].name
}

output "deployment_namespace" {
  description = "Namespace of the deployment"
  value       = kubernetes_deployment.main.metadata[0].namespace
}

output "deployment_labels" {
  description = "Labels applied to the deployment"
  value       = local.labels
}

output "selector_labels" {
  description = "Selector labels for service/HPA targeting"
  value       = local.selector_labels
}

# =============================================================================
# Service Outputs
# =============================================================================

output "service_name" {
  description = "Name of the Kubernetes service"
  value       = kubernetes_service.main.metadata[0].name
}

output "service_port" {
  description = "Service port number"
  value       = var.service_port
}

output "service_cluster_ip" {
  description = "ClusterIP of the service"
  value       = kubernetes_service.main.spec[0].cluster_ip
}

output "service_endpoint" {
  description = "Internal service endpoint (service.namespace.svc.cluster.local)"
  value       = "${kubernetes_service.main.metadata[0].name}.${kubernetes_service.main.metadata[0].namespace}.svc.cluster.local"
}

# =============================================================================
# Ingress Outputs
# =============================================================================

output "ingress_enabled" {
  description = "Whether ingress is enabled"
  value       = var.enable_ingress
}

output "ingress_host" {
  description = "Ingress hostname (if enabled)"
  value       = var.enable_ingress ? var.ingress_host : null
}

output "ingress_url" {
  description = "Full URL for the ingress (if enabled)"
  value       = var.enable_ingress && var.enable_tls ? "https://${var.ingress_host}" : (var.enable_ingress ? "http://${var.ingress_host}" : null)
}

# =============================================================================
# HPA Outputs
# =============================================================================

output "hpa_enabled" {
  description = "Whether HPA is enabled"
  value       = var.enable_hpa
}

output "hpa_name" {
  description = "Name of the HPA (if enabled)"
  value       = var.enable_hpa ? kubernetes_horizontal_pod_autoscaler_v2.main[0].metadata[0].name : null
}

output "hpa_min_replicas" {
  description = "Minimum replicas configured for HPA"
  value       = var.min_replicas
}

output "hpa_max_replicas" {
  description = "Maximum replicas configured for HPA"
  value       = var.max_replicas
}

output "hpa_scaling_config" {
  description = "HPA scaling configuration summary"
  value = {
    min_replicas          = var.min_replicas
    max_replicas          = var.max_replicas
    cpu_target_percent    = var.cpu_target_percent
    memory_target_percent = var.memory_target_percent
  }
}

# =============================================================================
# Resource Configuration Outputs
# =============================================================================

output "resource_config" {
  description = "Resource requests and limits configuration"
  value = {
    cpu_request    = var.cpu_request
    cpu_limit      = var.cpu_limit
    memory_request = var.memory_request
    memory_limit   = var.memory_limit
  }
}

# =============================================================================
# Health Check Outputs
# =============================================================================

output "health_check_config" {
  description = "Health check configuration"
  value = {
    path                    = var.health_check_path
    liveness_enabled        = var.enable_liveness_probe
    readiness_enabled       = var.enable_readiness_probe
    liveness_initial_delay  = var.liveness_initial_delay
    readiness_initial_delay = var.readiness_initial_delay
  }
}

# =============================================================================
# Monitoring Outputs
# =============================================================================

output "prometheus_scrape_config" {
  description = "Prometheus scrape configuration"
  value = {
    enabled = var.enable_prometheus_scrape
    port    = var.metrics_port
    path    = var.metrics_path
  }
}
