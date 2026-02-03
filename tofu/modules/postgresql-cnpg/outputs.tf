# CloudNativePG PostgreSQL Cluster Module - Outputs
#
# Connection strings and cluster information for application integration.

# =============================================================================
# Cluster Information
# =============================================================================

output "cluster_name" {
  description = "Name of the PostgreSQL cluster"
  value       = var.name
}

output "namespace" {
  description = "Namespace where cluster is deployed"
  value       = var.namespace
}

output "instances" {
  description = "Number of PostgreSQL instances"
  value       = var.instances
}

output "database_name" {
  description = "Name of the created database"
  value       = var.database_name
}

output "owner_name" {
  description = "Database owner/application user"
  value       = var.owner_name
}

# =============================================================================
# Connection Information
# =============================================================================

output "host_rw" {
  description = "Read-write service hostname (primary)"
  value       = "${var.name}-rw.${var.namespace}.svc.cluster.local"
}

output "host_ro" {
  description = "Read-only service hostname (replicas)"
  value       = "${var.name}-ro.${var.namespace}.svc.cluster.local"
}

output "host_r" {
  description = "Any instance service hostname (round-robin)"
  value       = "${var.name}-r.${var.namespace}.svc.cluster.local"
}

output "port" {
  description = "PostgreSQL port"
  value       = 5432
}

# =============================================================================
# Connection Strings (without password)
# =============================================================================

output "connection_string_rw" {
  description = "Read-write connection string (get password from credentials secret)"
  value       = "postgresql://${var.owner_name}@${var.name}-rw.${var.namespace}.svc.cluster.local:5432/${var.database_name}?sslmode=require"
}

output "connection_string_ro" {
  description = "Read-only connection string (get password from credentials secret)"
  value       = "postgresql://${var.owner_name}@${var.name}-ro.${var.namespace}.svc.cluster.local:5432/${var.database_name}?sslmode=require"
}

# =============================================================================
# Secret References
# =============================================================================

output "credentials_secret_name" {
  description = "Name of the Kubernetes secret containing application credentials"
  value       = kubernetes_secret.app_credentials.metadata[0].name
}

output "app_password" {
  description = "Application user password (sensitive)"
  value       = var.generate_password ? random_password.app_password[0].result : var.app_password
  sensitive   = true
}

output "database_url" {
  description = "Full DATABASE_URL for application configuration (sensitive)"
  value       = "postgresql://${var.owner_name}:${var.generate_password ? random_password.app_password[0].result : var.app_password}@${var.name}-rw.${var.namespace}.svc.cluster.local:5432/${var.database_name}?sslmode=require"
  sensitive   = true
}

output "database_url_ro" {
  description = "Read-only DATABASE_URL for application configuration (sensitive)"
  value       = "postgresql://${var.owner_name}:${var.generate_password ? random_password.app_password[0].result : var.app_password}@${var.name}-ro.${var.namespace}.svc.cluster.local:5432/${var.database_name}?sslmode=require"
  sensitive   = true
}

# =============================================================================
# CNPG-Managed Secrets (created by operator)
# =============================================================================

output "cnpg_app_secret" {
  description = "Name of CNPG-managed application secret (contains credentials)"
  value       = "${var.name}-app"
}

output "cnpg_superuser_secret" {
  description = "Name of CNPG-managed superuser secret (for emergencies only)"
  value       = "${var.name}-superuser"
}

# =============================================================================
# Backup Information
# =============================================================================

output "backup_enabled" {
  description = "Whether backup is enabled"
  value       = var.enable_backup
}

output "backup_bucket" {
  description = "S3 bucket for backups"
  value       = var.enable_backup ? var.backup_s3_bucket : ""
}

output "backup_retention" {
  description = "Backup retention policy"
  value       = var.backup_retention_policy
}

# =============================================================================
# Labels for Network Policies
# =============================================================================

output "pod_selector_labels" {
  description = "Labels for selecting PostgreSQL pods (use in NetworkPolicy)"
  value = {
    "cnpg.io/cluster" = var.name
  }
}
