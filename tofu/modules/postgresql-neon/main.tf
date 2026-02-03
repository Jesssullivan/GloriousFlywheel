# Neon PostgreSQL Module
#
# Provisions a PostgreSQL database on Neon serverless platform
# for metadata storage. Designed for stateless cache services.
#
# Usage:
#   module "attic_db" {
#     source = "../../modules/postgresql-neon"
#
#     project_name  = "attic-cache"
#     database_name = "attic"
#     branch_name   = "main"
#   }
#
# Note: This module uses the Neon API directly via the Neon Terraform provider.
# Neon free tier includes:
#   - 0.5 GB storage
#   - 1 compute (shared)
#   - Autoscaling 0.25-2 CU
#
# For existing Neon infrastructure, use the data sources to reference
# existing projects/databases rather than creating new ones.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# Data Sources - Reference Existing Infrastructure
# =============================================================================

# Use existing Neon project if project_id is provided
data "neon_project" "existing" {
  count = var.project_id != "" ? 1 : 0
  id    = var.project_id
}

# =============================================================================
# Neon Project (if creating new)
# =============================================================================

resource "neon_project" "main" {
  count = var.project_id == "" && var.create_project ? 1 : 0

  name   = var.project_name
  region = var.neon_region

  # Compute settings
  default_endpoint_settings {
    autoscaling_limit_min_cu = var.compute_min_cu
    autoscaling_limit_max_cu = var.compute_max_cu
    suspend_timeout_seconds  = var.suspend_timeout_seconds
  }

  # Enable pooler for connection pooling
  enable_logical_replication = var.enable_logical_replication

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Database Branch
# =============================================================================

resource "neon_branch" "main" {
  count = var.create_branch ? 1 : 0

  project_id = local.project_id
  name       = var.branch_name

  # Parent branch (defaults to main/default)
  parent_id = var.parent_branch_id
}

# =============================================================================
# Database
# =============================================================================

resource "neon_database" "main" {
  count = var.create_database ? 1 : 0

  project_id = local.project_id
  branch_id  = local.branch_id
  name       = var.database_name
  owner_name = local.role_name
}

# =============================================================================
# Role (User)
# =============================================================================

resource "neon_role" "main" {
  count = var.create_role ? 1 : 0

  project_id = local.project_id
  branch_id  = local.branch_id
  name       = var.role_name
}

# Generate random password for role if not provided
resource "random_password" "role_password" {
  count = var.create_role && var.role_password == "" ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# =============================================================================
# Endpoint (Compute)
# =============================================================================

resource "neon_endpoint" "main" {
  count = var.create_endpoint ? 1 : 0

  project_id = local.project_id
  branch_id  = local.branch_id
  type       = "read_write"

  autoscaling_limit_min_cu = var.compute_min_cu
  autoscaling_limit_max_cu = var.compute_max_cu
  suspend_timeout_seconds  = var.suspend_timeout_seconds

  # Enable pooler
  pooler_enabled = var.enable_pooler
  pooler_mode    = var.pooler_mode
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Determine project ID (existing or created)
  project_id = var.project_id != "" ? var.project_id : (
    var.create_project ? neon_project.main[0].id : ""
  )

  # Determine branch ID
  branch_id = var.branch_id != "" ? var.branch_id : (
    var.create_branch ? neon_branch.main[0].id : ""
  )

  # Role name
  role_name = var.create_role ? neon_role.main[0].name : var.role_name

  # Role password
  role_password = var.role_password != "" ? var.role_password : (
    var.create_role ? random_password.role_password[0].result : ""
  )

  # Build connection string
  # Format: postgresql://user:password@host/database?sslmode=require
  connection_host = var.create_endpoint ? neon_endpoint.main[0].host : var.endpoint_host

  connection_string = var.create_database ? (
    "postgresql://${local.role_name}:${local.role_password}@${local.connection_host}/${var.database_name}?sslmode=require"
  ) : ""

  # Pooler connection string (for high connection count apps)
  pooler_connection_string = var.enable_pooler && var.create_database ? (
    "postgresql://${local.role_name}:${local.role_password}@${local.connection_host}:5432/${var.database_name}?sslmode=require&options=endpoint%3D${var.create_endpoint ? neon_endpoint.main[0].id : ""}"
  ) : ""
}

# =============================================================================
# Outputs
# =============================================================================

output "project_id" {
  description = "Neon project ID"
  value       = local.project_id
}

output "branch_id" {
  description = "Neon branch ID"
  value       = local.branch_id
}

output "database_name" {
  description = "Database name"
  value       = var.database_name
}

output "role_name" {
  description = "Database role/user name"
  value       = local.role_name
}

output "role_password" {
  description = "Database role password"
  value       = local.role_password
  sensitive   = true
}

output "host" {
  description = "Database host"
  value       = local.connection_host
}

output "connection_string" {
  description = "PostgreSQL connection string"
  value       = local.connection_string
  sensitive   = true
}

output "pooler_connection_string" {
  description = "PostgreSQL pooler connection string (for high concurrency)"
  value       = local.pooler_connection_string
  sensitive   = true
}

output "endpoint_id" {
  description = "Neon endpoint ID"
  value       = var.create_endpoint ? neon_endpoint.main[0].id : ""
}

# =============================================================================
# Variables
# =============================================================================

variable "project_name" {
  description = "Name for new Neon project"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "Existing Neon project ID (if using existing)"
  type        = string
  default     = ""
}

variable "neon_region" {
  description = "Neon region for new project"
  type        = string
  default     = "aws-us-east-1"

  validation {
    condition = contains([
      "aws-us-east-1", "aws-us-east-2", "aws-us-west-2",
      "aws-eu-central-1", "aws-ap-southeast-1"
    ], var.neon_region)
    error_message = "Must be a valid Neon region"
  }
}

variable "create_project" {
  description = "Create a new Neon project"
  type        = bool
  default     = false
}

variable "branch_name" {
  description = "Name for the database branch"
  type        = string
  default     = "main"
}

variable "branch_id" {
  description = "Existing branch ID (if using existing)"
  type        = string
  default     = ""
}

variable "parent_branch_id" {
  description = "Parent branch ID for branching"
  type        = string
  default     = ""
}

variable "create_branch" {
  description = "Create a new branch"
  type        = bool
  default     = false
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "app"
}

variable "create_database" {
  description = "Create the database"
  type        = bool
  default     = true
}

variable "role_name" {
  description = "Database role/user name"
  type        = string
  default     = "app"
}

variable "role_password" {
  description = "Database role password (generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "create_role" {
  description = "Create the database role"
  type        = bool
  default     = true
}

variable "endpoint_host" {
  description = "Existing endpoint host (if not creating)"
  type        = string
  default     = ""
}

variable "create_endpoint" {
  description = "Create a compute endpoint"
  type        = bool
  default     = true
}

variable "compute_min_cu" {
  description = "Minimum compute units for autoscaling"
  type        = number
  default     = 0.25

  validation {
    condition     = var.compute_min_cu >= 0.25
    error_message = "compute_min_cu must be at least 0.25"
  }
}

variable "compute_max_cu" {
  description = "Maximum compute units for autoscaling"
  type        = number
  default     = 2

  validation {
    condition     = var.compute_max_cu >= 0.25
    error_message = "compute_max_cu must be at least 0.25"
  }
}

variable "suspend_timeout_seconds" {
  description = "Seconds of inactivity before compute suspends (0 = never)"
  type        = number
  default     = 300

  validation {
    condition     = var.suspend_timeout_seconds >= 0
    error_message = "suspend_timeout_seconds must be non-negative"
  }
}

variable "enable_pooler" {
  description = "Enable connection pooler (PgBouncer)"
  type        = bool
  default     = true
}

variable "pooler_mode" {
  description = "Pooler mode: transaction or session"
  type        = string
  default     = "transaction"

  validation {
    condition     = contains(["transaction", "session"], var.pooler_mode)
    error_message = "pooler_mode must be 'transaction' or 'session'"
  }
}

variable "enable_logical_replication" {
  description = "Enable logical replication on project"
  type        = bool
  default     = false
}
