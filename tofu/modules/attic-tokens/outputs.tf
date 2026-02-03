# Attic Token Management Module - Outputs
#
# All token values are marked as sensitive to prevent exposure in logs.

# =============================================================================
# CI Token Outputs
# =============================================================================

output "ci_token_ids" {
  description = "Map of CI token names to their token IDs (for revocation)"
  value = {
    for name, _ in var.ci_tokens : name => random_id.ci_token_ids[name].hex
  }
}

output "ci_tokens" {
  description = "Map of CI token names to their token secrets"
  value = {
    for name, _ in var.ci_tokens : name => random_password.ci_tokens[name].result
  }
  sensitive = true
}

output "ci_tokens_secret_name" {
  description = "Name of the Kubernetes secret containing CI tokens"
  value       = kubernetes_secret.ci_tokens.metadata[0].name
}

output "ci_tokens_expiry" {
  description = "Expiry timestamp for CI tokens"
  value       = local.ci_token_expiry
}

# =============================================================================
# Read-Only Token Outputs
# =============================================================================

output "readonly_token_ids" {
  description = "Map of read-only token names to their token IDs"
  value = {
    for name, _ in var.readonly_tokens : name => random_id.readonly_token_ids[name].hex
  }
}

output "readonly_tokens" {
  description = "Map of read-only token names to their token secrets"
  value = {
    for name, _ in var.readonly_tokens : name => random_password.readonly_tokens[name].result
  }
  sensitive = true
}

output "readonly_tokens_secret_name" {
  description = "Name of the Kubernetes secret containing read-only tokens"
  value       = kubernetes_secret.readonly_tokens.metadata[0].name
}

# =============================================================================
# Service Token Outputs
# =============================================================================

output "service_token_ids" {
  description = "Map of service token names to their token IDs"
  value = {
    for name, _ in var.service_tokens : name => random_id.service_token_ids[name].hex
  }
}

output "service_tokens" {
  description = "Map of service token names to their token secrets"
  value = {
    for name, _ in var.service_tokens : name => random_password.service_tokens[name].result
  }
  sensitive = true
}

output "service_tokens_secret_name" {
  description = "Name of the Kubernetes secret containing service tokens"
  value       = kubernetes_secret.service_tokens.metadata[0].name
}

output "service_tokens_expiry" {
  description = "Expiry timestamp for service tokens"
  value       = local.service_token_expiry
}

# =============================================================================
# Root Token Outputs
# =============================================================================

output "root_token_id" {
  description = "Root token ID (for revocation)"
  value       = var.create_root_token ? random_id.root_token_id[0].hex : null
}

output "root_token" {
  description = "Root token secret"
  value       = var.create_root_token ? random_password.root_token[0].result : null
  sensitive   = true
}

output "root_token_secret_name" {
  description = "Name of the Kubernetes secret containing root token"
  value       = var.create_root_token ? kubernetes_secret.root_token[0].metadata[0].name : null
}

output "root_token_expiry" {
  description = "Expiry timestamp for root token"
  value       = var.create_root_token ? local.root_token_expiry : null
}

# =============================================================================
# Rotation Information
# =============================================================================

output "ci_token_rotation_date" {
  description = "Date when CI tokens were last rotated"
  value       = time_rotating.ci_tokens.rotation_rfc3339
}

output "ci_token_next_rotation" {
  description = "Date when CI tokens will next be rotated"
  value       = timeadd(time_rotating.ci_tokens.rotation_rfc3339, "${var.ci_token_validity_days * 24}h")
}

output "service_token_rotation_date" {
  description = "Date when service tokens were last rotated"
  value       = time_rotating.service_tokens.rotation_rfc3339
}

output "service_token_next_rotation" {
  description = "Date when service tokens will next be rotated"
  value       = timeadd(time_rotating.service_tokens.rotation_rfc3339, "${var.service_token_validity_days * 24}h")
}

output "root_token_rotation_date" {
  description = "Date when root token was last rotated"
  value       = time_rotating.root_token.rotation_rfc3339
}

output "root_token_next_rotation" {
  description = "Date when root token will next be rotated"
  value       = timeadd(time_rotating.root_token.rotation_rfc3339, "${var.root_token_validity_days * 24}h")
}

# =============================================================================
# Revocation List
# =============================================================================

output "revocation_list_configmap" {
  description = "Name of the ConfigMap containing the token revocation list"
  value       = kubernetes_config_map.revocation_list.metadata[0].name
}

output "revocation_list_revision" {
  description = "Current revision of the revocation list"
  value       = var.revocation_list_revision
}

# =============================================================================
# RBAC Outputs
# =============================================================================

output "token_accessor_sa_name" {
  description = "Name of the ServiceAccount for token access"
  value       = var.create_token_accessor_sa ? kubernetes_service_account.token_accessor[0].metadata[0].name : null
}

# =============================================================================
# Summary Output
# =============================================================================

output "token_summary" {
  description = "Summary of all generated tokens (no secrets)"
  value = {
    ci_tokens = {
      count      = length(var.ci_tokens)
      names      = keys(var.ci_tokens)
      expires_at = local.ci_token_expiry
    }
    readonly_tokens = {
      count      = length(var.readonly_tokens)
      names      = keys(var.readonly_tokens)
      expires_at = local.ci_token_expiry
    }
    service_tokens = {
      count      = length(var.service_tokens)
      names      = keys(var.service_tokens)
      expires_at = local.service_token_expiry
    }
    root_token = {
      exists     = var.create_root_token
      expires_at = var.create_root_token ? local.root_token_expiry : null
    }
  }
}
