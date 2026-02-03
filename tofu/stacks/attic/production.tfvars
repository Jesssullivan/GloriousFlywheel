# Production Environment Configuration
# =====================================
#
# Full HA configuration for production.
# Production should own its resources - never adopt.

environment = "production"
namespace   = "nix-cache"

# Production should always create its own resources
adopt_existing_namespace    = false
adopt_existing_object_store = false

# Full HA configuration
pg_instances     = 3
pg_storage_size  = "10Gi"
api_min_replicas = 2
api_max_replicas = 10

# Full features enabled
pg_enable_backup        = true
enable_token_management = true

# Production ingress
ingress_host      = "nix-cache.fuzzy-dev.tinyland.dev"
enable_staging_dns = false
