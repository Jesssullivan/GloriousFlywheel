# DNS Record Module - Outputs
#
# Outputs for integration with other modules.

# =============================================================================
# Record Information
# =============================================================================

output "record_count" {
  description = "Number of DNS records managed"
  value       = length(var.records)
}

output "provider" {
  description = "DNS provider type in use"
  value       = var.provider_type
}

output "domain" {
  description = "Base domain for records"
  value       = var.domain
}

# =============================================================================
# Integration Helpers
# =============================================================================

output "ingress_annotations" {
  description = "Annotations to add to Kubernetes Ingress for external-dns"
  value = var.provider_type == "external-dns" ? merge(
    {
      "external-dns.alpha.kubernetes.io/ttl" = tostring(var.default_ttl)
    },
    length(var.records) > 0 ? {
      "external-dns.alpha.kubernetes.io/hostname" = join(",", [for name, record in var.records : "${name}.${var.domain}"])
    } : {}
  ) : {}
}

output "record_urls" {
  description = "Map of record names to their full URLs (https://)"
  value = {
    for name, record in var.records : name => "https://${name}.${var.domain}"
  }
}
