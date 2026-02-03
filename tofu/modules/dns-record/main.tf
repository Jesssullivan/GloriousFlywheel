# DNS Record Module
#
# Reusable module for DNS record management supporting multiple providers:
# - DreamHost API
# - External-dns annotations (Kubernetes native)
#
# Note: Cloudflare support has been removed. Use external-dns with Cloudflare
# webhook if Cloudflare DNS is needed.
#
# Usage:
#   module "dns" {
#     source = "../../modules/dns-record"
#
#     provider_type = "external-dns"
#     domain        = "fuzzy-dev.tinyland.dev"
#
#     records = {
#       "nix-cache" = {
#         type  = "A"
#         value = "212.2.244.217"
#       }
#     }
#   }

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Normalize record entries
  records_list = [
    for name, record in var.records : {
      name    = name
      type    = record.type
      value   = record.value
      ttl     = lookup(record, "ttl", var.default_ttl)
      proxied = lookup(record, "proxied", false)
      fqdn    = "${name}.${var.domain}"
    }
  ]

  # Filter by provider type
  dreamhost_records    = var.provider_type == "dreamhost" ? local.records_list : []
  external_dns_records = var.provider_type == "external-dns" ? local.records_list : []
}

# =============================================================================
# DreamHost DNS Provider
# =============================================================================

# DreamHost API requires direct HTTP calls
# API Documentation: https://help.dreamhost.com/hc/en-us/articles/217560167-API-overview
resource "terraform_data" "dreamhost_dns" {
  for_each = var.provider_type == "dreamhost" ? { for r in local.dreamhost_records : r.name => r } : {}

  input = {
    record_name      = each.value.fqdn
    record_type      = each.value.type
    record_value     = each.value.value
    comment          = var.dreamhost_comment
    dreamhost_api_key = var.dreamhost_api_key
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Add DNS record via DreamHost API
      curl -s "https://api.dreamhost.com/?key=${var.dreamhost_api_key}&cmd=dns-add_record&record=${each.value.fqdn}&type=${each.value.type}&value=${each.value.value}&comment=${urlencode(var.dreamhost_comment)}"
    EOT

    environment = {
      DREAMHOST_API_KEY = var.dreamhost_api_key
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Remove DNS record via DreamHost API
      curl -s "https://api.dreamhost.com/?key=${self.input.dreamhost_api_key}&cmd=dns-remove_record&record=${self.input.record_name}&type=${self.input.record_type}&value=${self.input.record_value}"
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# External-DNS Annotations (Output Only)
# =============================================================================
#
# External-dns reads annotations from Ingress/Service resources.
# This module outputs the required annotations for use in other resources.
#
# Usage in Ingress:
#   annotations:
#     external-dns.alpha.kubernetes.io/hostname: nix-cache.fuzzy-dev.tinyland.dev
#     external-dns.alpha.kubernetes.io/ttl: "300"

locals {
  external_dns_annotations = {
    for r in local.external_dns_records : r.name => {
      "external-dns.alpha.kubernetes.io/hostname" = r.fqdn
      "external-dns.alpha.kubernetes.io/ttl"      = tostring(r.ttl)
    }
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "records" {
  description = "Map of created DNS records"
  value = {
    for r in local.records_list : r.name => {
      fqdn  = r.fqdn
      type  = r.type
      value = r.value
      ttl   = r.ttl
    }
  }
}

output "fqdns" {
  description = "List of fully qualified domain names"
  value = [for r in local.records_list : r.fqdn]
}

output "external_dns_annotations" {
  description = "Annotations for external-dns integration"
  value = local.external_dns_annotations
}

output "dreamhost_records" {
  description = "DreamHost records created (if using DreamHost)"
  value = var.provider_type == "dreamhost" ? {
    for k, v in terraform_data.dreamhost_dns : k => {
      fqdn  = v.input.record_name
      type  = v.input.record_type
      value = v.input.record_value
    }
  } : {}
}
