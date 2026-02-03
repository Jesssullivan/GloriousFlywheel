# Civo Object Storage Module
#
# Provisions S3-compatible object storage on Civo for use with
# cache services (Attic, Quay, Pulp) and artifact storage.
#
# Usage:
#   module "cache_storage" {
#     source = "../../modules/civo-object-store"
#
#     name   = "nix-cache"
#     region = "NYC1"
#
#     # Optional: configure max size and access
#     max_size_gb = 500
#     access_key_id = var.existing_access_key_id  # Or let module create one
#   }
#
# Outputs:
#   - bucket_name: Name of the created bucket
#   - endpoint: S3 endpoint URL
#   - access_key_id: Access key for S3 authentication
#   - secret_access_key: Secret key for S3 authentication (sensitive)
#
# Civo Object Storage:
#   - S3-compatible API
#   - Free and unlimited egress/ingress
#   - 500GB allocation blocks
#   - Endpoint: objectstore.<region>.civo.com

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    civo = {
      source  = "civo/civo"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Civo object storage endpoints by region
  endpoints = {
    "NYC1" = "objectstore.nyc1.civo.com"
    "LON1" = "objectstore.lon1.civo.com"
    "FRA1" = "objectstore.fra1.civo.com"
    "PHX1" = "objectstore.phx1.civo.com"
  }

  endpoint = local.endpoints[var.region]

  # Generate unique bucket name if not provided
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.name}-${random_id.bucket_suffix[0].hex}"

  # Labels for resource management
  labels = merge(
    {
      "managed-by" = "opentofu"
      "project"    = var.name
    },
    var.additional_labels
  )
}

# =============================================================================
# Random Suffix for Bucket Name
# =============================================================================

resource "random_id" "bucket_suffix" {
  count       = var.bucket_name == "" ? 1 : 0
  byte_length = 4
}

# =============================================================================
# Object Store Credentials
# =============================================================================

resource "civo_object_store_credential" "main" {
  count = var.create_credentials ? 1 : 0

  name   = "${var.name}-credentials"
  region = var.region
}

# =============================================================================
# Object Store Bucket
# =============================================================================

resource "civo_object_store" "main" {
  name   = local.bucket_name
  region = var.region

  # Max size in GB (Civo uses 500GB blocks)
  max_size_gb = var.max_size_gb

  # Link to credentials
  access_key_id = var.create_credentials ? civo_object_store_credential.main[0].access_key_id : var.access_key_id

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "bucket_name" {
  description = "Name of the object store bucket"
  value       = civo_object_store.main.name
}

output "bucket_id" {
  description = "Civo object store ID"
  value       = civo_object_store.main.id
}

output "endpoint" {
  description = "S3 endpoint URL (without https://)"
  value       = local.endpoint
}

output "endpoint_url" {
  description = "Full S3 endpoint URL"
  value       = "https://${local.endpoint}"
}

output "region" {
  description = "Civo region for the bucket"
  value       = var.region
}

output "max_size_gb" {
  description = "Maximum size of the bucket in GB"
  value       = var.max_size_gb
}

output "access_key_id" {
  description = "Access key ID for S3 authentication"
  value       = var.create_credentials ? civo_object_store_credential.main[0].access_key_id : var.access_key_id
}

output "secret_access_key" {
  description = "Secret access key for S3 authentication"
  value       = var.create_credentials ? civo_object_store_credential.main[0].secret_access_key : null
  sensitive   = true
}

output "s3_config" {
  description = "S3 configuration for applications"
  value = {
    bucket   = civo_object_store.main.name
    region   = var.region
    endpoint = "https://${local.endpoint}"
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "name" {
  description = "Name prefix for the object store resources"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "Name must be lowercase alphanumeric with optional hyphens"
  }
}

variable "bucket_name" {
  description = "Explicit bucket name (if empty, generates unique name)"
  type        = string
  default     = ""
}

variable "region" {
  description = "Civo region for object storage"
  type        = string
  default     = "NYC1"

  validation {
    condition     = contains(["NYC1", "LON1", "FRA1", "PHX1"], var.region)
    error_message = "Region must be one of: NYC1, LON1, FRA1, PHX1"
  }
}

variable "max_size_gb" {
  description = "Maximum size in GB (Civo uses 500GB blocks)"
  type        = number
  default     = 500

  validation {
    condition     = var.max_size_gb >= 500
    error_message = "max_size_gb must be at least 500 (Civo minimum allocation)"
  }
}

variable "create_credentials" {
  description = "Create new object store credentials"
  type        = bool
  default     = true
}

variable "access_key_id" {
  description = "Existing access key ID (required if create_credentials is false)"
  type        = string
  default     = ""
}

variable "additional_labels" {
  description = "Additional labels for resource management"
  type        = map(string)
  default     = {}
}
