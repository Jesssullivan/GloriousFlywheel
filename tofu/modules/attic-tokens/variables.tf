# Attic Token Management Module - Variables
#
# Configuration variables for token generation and management.

# =============================================================================
# Namespace & Environment
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for token secrets"
  type        = string
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "environment must be one of: production, staging, development"
  }
}

variable "part_of" {
  description = "Part-of label value"
  type        = string
  default     = "nix-cache"
}

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Token Validity Periods
# =============================================================================

variable "ci_token_validity_days" {
  description = "Validity period for CI tokens in days"
  type        = number
  default     = 90

  validation {
    condition     = var.ci_token_validity_days >= 1 && var.ci_token_validity_days <= 365
    error_message = "ci_token_validity_days must be between 1 and 365"
  }
}

variable "service_token_validity_days" {
  description = "Validity period for service tokens in days"
  type        = number
  default     = 365

  validation {
    condition     = var.service_token_validity_days >= 1 && var.service_token_validity_days <= 730
    error_message = "service_token_validity_days must be between 1 and 730"
  }
}

variable "root_token_validity_days" {
  description = "Validity period for root token in days"
  type        = number
  default     = 180

  validation {
    condition     = var.root_token_validity_days >= 1 && var.root_token_validity_days <= 365
    error_message = "root_token_validity_days must be between 1 and 365"
  }
}

# =============================================================================
# CI Tokens Configuration
# =============================================================================

variable "ci_tokens" {
  description = "Map of CI tokens to create. Key is token name, value is config."
  type = map(object({
    permissions = list(string) # e.g., ["push", "pull"]
    caches      = list(string) # e.g., ["main", "staging"]
    description = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, config in var.ci_tokens :
      alltrue([for perm in config.permissions : contains(["push", "pull", "delete", "admin"], perm)])
    ])
    error_message = "permissions must be one of: push, pull, delete, admin"
  }
}

# =============================================================================
# Read-Only Tokens Configuration
# =============================================================================

variable "readonly_tokens" {
  description = "Map of read-only tokens to create. Key is token name, value is config."
  type = map(object({
    caches      = list(string)
    description = optional(string, "")
  }))
  default = {}
}

# =============================================================================
# Service Tokens Configuration
# =============================================================================

variable "service_tokens" {
  description = "Map of service tokens to create. Key is token name, value is config."
  type = map(object({
    permissions = list(string)
    caches      = list(string)
    description = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, config in var.service_tokens :
      alltrue([for perm in config.permissions : contains(["push", "pull", "delete", "admin", "*"], perm)])
    ])
    error_message = "permissions must be one of: push, pull, delete, admin, *"
  }
}

# =============================================================================
# Root Token Configuration
# =============================================================================

variable "create_root_token" {
  description = "Whether to create a root admin token"
  type        = bool
  default     = true
}

# =============================================================================
# Secret Names
# =============================================================================

variable "ci_tokens_secret_name" {
  description = "Name of the Kubernetes secret for CI tokens"
  type        = string
  default     = "attic-ci-tokens"
}

variable "readonly_tokens_secret_name" {
  description = "Name of the Kubernetes secret for read-only tokens"
  type        = string
  default     = "attic-readonly-tokens"
}

variable "service_tokens_secret_name" {
  description = "Name of the Kubernetes secret for service tokens"
  type        = string
  default     = "attic-service-tokens"
}

variable "root_token_secret_name" {
  description = "Name of the Kubernetes secret for root token"
  type        = string
  default     = "attic-root-token"
}

# =============================================================================
# Token Revocation
# =============================================================================

variable "revoked_token_ids" {
  description = "List of revoked token IDs (JTI claims)"
  type        = list(string)
  default     = []
}

variable "revocation_list_revision" {
  description = "Revision number for the revocation list"
  type        = number
  default     = 1
}

# =============================================================================
# RBAC Configuration
# =============================================================================

variable "create_token_accessor_sa" {
  description = "Create a ServiceAccount with read access to tokens"
  type        = bool
  default     = true
}
