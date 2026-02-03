# Staging Environment Configuration
# ==================================
#
# Reduced resources for staging environment.
# Use adopt_existing_namespace=true if namespace already exists.

environment = "staging"
namespace   = "nix-cache-staging"

# Resource Recovery - set to true to adopt existing resources
# Use this when resources exist but are not in Terraform state
adopt_existing_namespace    = true
adopt_existing_object_store = false

# Reduced HA configuration for staging
pg_instances     = 1
pg_storage_size  = "5Gi"
api_min_replicas = 1
api_max_replicas = 3

# Disable expensive features in staging
pg_enable_backup        = false
enable_token_management = false

# Staging-specific ingress
ingress_host      = "nix-cache-staging.fuzzy-dev.tinyland.dev"
enable_staging_dns = false
