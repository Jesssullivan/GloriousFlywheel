# DNS Record Module - Variables
#
# Configuration variables for DNS record management.

# =============================================================================
# Provider Selection
# =============================================================================

variable "provider_type" {
  description = "DNS provider type (dreamhost, external-dns)"
  type        = string
  default     = "external-dns"

  validation {
    condition     = contains(["dreamhost", "external-dns"], var.provider_type)
    error_message = "provider_type must be one of: dreamhost, external-dns"
  }
}

# =============================================================================
# Domain Configuration
# =============================================================================

variable "domain" {
  description = "Base domain for DNS records (e.g., fuzzy-dev.tinyland.dev)"
  type        = string
}

variable "records" {
  description = "Map of DNS records to create"
  type = map(object({
    type    = string
    value   = string
    ttl     = optional(number)
    proxied = optional(bool) # Cloudflare only
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, record in var.records : contains(["A", "AAAA", "CNAME", "TXT", "MX", "NS"], record.type)
    ])
    error_message = "Record type must be one of: A, AAAA, CNAME, TXT, MX, NS"
  }
}

variable "default_ttl" {
  description = "Default TTL for DNS records (seconds)"
  type        = number
  default     = 300

  validation {
    condition     = var.default_ttl >= 60 && var.default_ttl <= 86400
    error_message = "default_ttl must be between 60 and 86400 seconds"
  }
}

# =============================================================================
# DreamHost Configuration
# =============================================================================

variable "dreamhost_api_key" {
  description = "DreamHost API key (required if provider_type is dreamhost)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dreamhost_comment" {
  description = "Comment for DreamHost DNS records"
  type        = string
  default     = "Managed by OpenTofu"
}

# =============================================================================
# Metadata
# =============================================================================

variable "managed_by" {
  description = "Identifier for the managing system (used in record comments)"
  type        = string
  default     = "attic-cache"
}
