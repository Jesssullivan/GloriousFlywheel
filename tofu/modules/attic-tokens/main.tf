# Attic Token Management Module
#
# Generates and manages JWT tokens for Attic binary cache authentication.
# Tokens are stored in Kubernetes secrets for consumption by CI/CD pipelines.
#
# Token Hierarchy:
#   Root Token (admin) - Full administrative access
#   ├── CI Tokens (per-repo) - Push + Pull for specific caches
#   ├── Read-Only Tokens - Public pull access
#   └── Service Tokens - Internal services (GC worker, etc.)
#
# Security:
#   - All token outputs are marked sensitive
#   - Tokens are stored in K8s secrets with proper RBAC
#   - Token expiration is enforced via JWT claims
#   - Short-lived tokens for CI, longer for services

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Token expiry timestamps
  ci_token_expiry      = timeadd(timestamp(), "${var.ci_token_validity_days * 24}h")
  service_token_expiry = timeadd(timestamp(), "${var.service_token_validity_days * 24}h")
  root_token_expiry    = timeadd(timestamp(), "${var.root_token_validity_days * 24}h")

  # Common labels for all resources
  common_labels = merge(var.additional_labels, {
    "app.kubernetes.io/name"       = "attic"
    "app.kubernetes.io/component"  = "tokens"
    "app.kubernetes.io/managed-by" = "opentofu"
    "app.kubernetes.io/part-of"    = var.part_of
  })

  # Token metadata for audit
  token_metadata = {
    created_by  = "opentofu"
    created_at  = timestamp()
    environment = var.environment
  }
}

# =============================================================================
# Token Rotation Tracking
# =============================================================================

# Track when tokens were last rotated
resource "time_rotating" "ci_tokens" {
  rotation_days = var.ci_token_validity_days

  triggers = {
    # Force rotation if validity period changes
    validity_days = var.ci_token_validity_days
  }
}

resource "time_rotating" "service_tokens" {
  rotation_days = var.service_token_validity_days

  triggers = {
    validity_days = var.service_token_validity_days
  }
}

resource "time_rotating" "root_token" {
  rotation_days = var.root_token_validity_days

  triggers = {
    validity_days = var.root_token_validity_days
  }
}

# =============================================================================
# Token Generation - Random Secrets
# =============================================================================

# Generate unique token IDs for each token type
# These are used as JWT 'jti' (JWT ID) claims for revocation tracking

resource "random_id" "ci_token_ids" {
  for_each = var.ci_tokens

  byte_length = 16
  prefix      = "ci-${each.key}-"

  keepers = {
    rotation = time_rotating.ci_tokens.id
    scope    = jsonencode(each.value)
  }
}

resource "random_id" "readonly_token_ids" {
  for_each = var.readonly_tokens

  byte_length = 16
  prefix      = "ro-${each.key}-"

  keepers = {
    rotation = time_rotating.ci_tokens.id
    scope    = jsonencode(each.value)
  }
}

resource "random_id" "service_token_ids" {
  for_each = var.service_tokens

  byte_length = 16
  prefix      = "svc-${each.key}-"

  keepers = {
    rotation = time_rotating.service_tokens.id
    scope    = jsonencode(each.value)
  }
}

resource "random_id" "root_token_id" {
  count = var.create_root_token ? 1 : 0

  byte_length = 16
  prefix      = "root-"

  keepers = {
    rotation = time_rotating.root_token.id
  }
}

# =============================================================================
# Token Secret Generation
# =============================================================================

# Generate cryptographically secure token secrets
# These are combined with the JWT signing key to create signed tokens

resource "random_password" "ci_tokens" {
  for_each = var.ci_tokens

  length  = 64
  special = false

  keepers = {
    rotation = time_rotating.ci_tokens.id
  }
}

resource "random_password" "readonly_tokens" {
  for_each = var.readonly_tokens

  length  = 64
  special = false

  keepers = {
    rotation = time_rotating.ci_tokens.id
  }
}

resource "random_password" "service_tokens" {
  for_each = var.service_tokens

  length  = 64
  special = false

  keepers = {
    rotation = time_rotating.service_tokens.id
  }
}

resource "random_password" "root_token" {
  count = var.create_root_token ? 1 : 0

  length  = 64
  special = false

  keepers = {
    rotation = time_rotating.root_token.id
  }
}

# =============================================================================
# Kubernetes Secrets - CI Tokens
# =============================================================================

resource "kubernetes_secret" "ci_tokens" {
  metadata {
    name      = var.ci_tokens_secret_name
    namespace = var.namespace

    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "ci-tokens"
      "attic.dev/token-type"        = "ci"
    })

    annotations = {
      "attic.dev/rotation-date"    = time_rotating.ci_tokens.rotation_rfc3339
      "attic.dev/next-rotation"    = timeadd(time_rotating.ci_tokens.rotation_rfc3339, "${var.ci_token_validity_days * 24}h")
      "attic.dev/validity-days"    = tostring(var.ci_token_validity_days)
      "attic.dev/token-count"      = tostring(length(var.ci_tokens))
      "attic.dev/managed-by"       = "opentofu"
      "attic.dev/rotation-enabled" = "true"
    }
  }

  type = "Opaque"

  # Token data - one entry per CI configuration
  data = {
    for name, config in var.ci_tokens : name => jsonencode({
      token_id    = random_id.ci_token_ids[name].hex
      secret      = random_password.ci_tokens[name].result
      permissions = config.permissions
      caches      = config.caches
      expires_at  = local.ci_token_expiry
      created_at  = local.token_metadata.created_at
      sub         = "ci:${name}"
    })
  }

  lifecycle {
    # Prevent accidental deletion of tokens
    prevent_destroy = false
  }
}

# =============================================================================
# Kubernetes Secrets - Read-Only Tokens
# =============================================================================

resource "kubernetes_secret" "readonly_tokens" {
  metadata {
    name      = var.readonly_tokens_secret_name
    namespace = var.namespace

    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "readonly-tokens"
      "attic.dev/token-type"        = "readonly"
    })

    annotations = {
      "attic.dev/rotation-date"    = time_rotating.ci_tokens.rotation_rfc3339
      "attic.dev/next-rotation"    = timeadd(time_rotating.ci_tokens.rotation_rfc3339, "${var.ci_token_validity_days * 24}h")
      "attic.dev/validity-days"    = tostring(var.ci_token_validity_days)
      "attic.dev/token-count"      = tostring(length(var.readonly_tokens))
      "attic.dev/managed-by"       = "opentofu"
      "attic.dev/rotation-enabled" = "true"
    }
  }

  type = "Opaque"

  data = {
    for name, config in var.readonly_tokens : name => jsonencode({
      token_id    = random_id.readonly_token_ids[name].hex
      secret      = random_password.readonly_tokens[name].result
      permissions = ["pull"]
      caches      = config.caches
      expires_at  = local.ci_token_expiry
      created_at  = local.token_metadata.created_at
      sub         = "readonly:${name}"
    })
  }
}

# =============================================================================
# Kubernetes Secrets - Service Tokens
# =============================================================================

resource "kubernetes_secret" "service_tokens" {
  metadata {
    name      = var.service_tokens_secret_name
    namespace = var.namespace

    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "service-tokens"
      "attic.dev/token-type"        = "service"
    })

    annotations = {
      "attic.dev/rotation-date"    = time_rotating.service_tokens.rotation_rfc3339
      "attic.dev/next-rotation"    = timeadd(time_rotating.service_tokens.rotation_rfc3339, "${var.service_token_validity_days * 24}h")
      "attic.dev/validity-days"    = tostring(var.service_token_validity_days)
      "attic.dev/token-count"      = tostring(length(var.service_tokens))
      "attic.dev/managed-by"       = "opentofu"
      "attic.dev/rotation-enabled" = "true"
    }
  }

  type = "Opaque"

  data = {
    for name, config in var.service_tokens : name => jsonencode({
      token_id    = random_id.service_token_ids[name].hex
      secret      = random_password.service_tokens[name].result
      permissions = config.permissions
      caches      = config.caches
      expires_at  = local.service_token_expiry
      created_at  = local.token_metadata.created_at
      sub         = "service:${name}"
    })
  }
}

# =============================================================================
# Kubernetes Secrets - Root Token
# =============================================================================

resource "kubernetes_secret" "root_token" {
  count = var.create_root_token ? 1 : 0

  metadata {
    name      = var.root_token_secret_name
    namespace = var.namespace

    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "root-token"
      "attic.dev/token-type"        = "root"
    })

    annotations = {
      "attic.dev/rotation-date"    = time_rotating.root_token.rotation_rfc3339
      "attic.dev/next-rotation"    = timeadd(time_rotating.root_token.rotation_rfc3339, "${var.root_token_validity_days * 24}h")
      "attic.dev/validity-days"    = tostring(var.root_token_validity_days)
      "attic.dev/managed-by"       = "opentofu"
      "attic.dev/rotation-enabled" = "true"
      # Extra security annotations for root token
      "attic.dev/high-privilege"   = "true"
      "attic.dev/audit-required"   = "true"
    }
  }

  type = "Opaque"

  data = {
    "root" = jsonencode({
      token_id    = random_id.root_token_id[0].hex
      secret      = random_password.root_token[0].result
      permissions = ["*"]
      caches      = ["*"]
      expires_at  = local.root_token_expiry
      created_at  = local.token_metadata.created_at
      sub         = "root"
      admin       = true
    })
  }
}

# =============================================================================
# Token Revocation List ConfigMap
# =============================================================================

# Maintains a list of revoked token IDs (JTI claims) for validation
resource "kubernetes_config_map" "revocation_list" {
  metadata {
    name      = "attic-token-revocation-list"
    namespace = var.namespace

    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "revocation-list"
    })

    annotations = {
      "attic.dev/last-updated" = timestamp()
      "attic.dev/managed-by"   = "opentofu"
    }
  }

  data = {
    # JSON list of revoked token IDs
    "revoked_tokens.json" = jsonencode({
      revoked  = var.revoked_token_ids
      updated  = timestamp()
      revision = var.revocation_list_revision
    })
  }
}

# =============================================================================
# RBAC - ServiceAccount for Token Access
# =============================================================================

resource "kubernetes_service_account" "token_accessor" {
  count = var.create_token_accessor_sa ? 1 : 0

  metadata {
    name      = "attic-token-accessor"
    namespace = var.namespace

    labels = local.common_labels

    annotations = {
      "attic.dev/purpose" = "Provides controlled access to token secrets"
    }
  }
}

resource "kubernetes_role" "token_reader" {
  count = var.create_token_accessor_sa ? 1 : 0

  metadata {
    name      = "attic-token-reader"
    namespace = var.namespace

    labels = local.common_labels
  }

  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [
      var.ci_tokens_secret_name,
      var.readonly_tokens_secret_name,
    ]
    verbs = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    resource_names = [
      "attic-token-revocation-list",
    ]
    verbs = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "token_reader" {
  count = var.create_token_accessor_sa ? 1 : 0

  metadata {
    name      = "attic-token-reader"
    namespace = var.namespace

    labels = local.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.token_reader[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.token_accessor[0].metadata[0].name
    namespace = var.namespace
  }
}

# =============================================================================
# Audit ConfigMap - Token Usage Tracking
# =============================================================================

resource "kubernetes_config_map" "token_audit" {
  metadata {
    name      = "attic-token-audit"
    namespace = var.namespace

    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "audit"
    })
  }

  data = {
    # Token inventory for audit purposes (no secrets included)
    "token_inventory.json" = jsonencode({
      ci_tokens = {
        for name, config in var.ci_tokens : name => {
          token_id   = random_id.ci_token_ids[name].hex
          caches     = config.caches
          permissions = config.permissions
          expires_at = local.ci_token_expiry
        }
      }
      readonly_tokens = {
        for name, config in var.readonly_tokens : name => {
          token_id   = random_id.readonly_token_ids[name].hex
          caches     = config.caches
          permissions = ["pull"]
          expires_at = local.ci_token_expiry
        }
      }
      service_tokens = {
        for name, config in var.service_tokens : name => {
          token_id   = random_id.service_token_ids[name].hex
          caches     = config.caches
          permissions = config.permissions
          expires_at = local.service_token_expiry
        }
      }
      root_token_exists = var.create_root_token
      generated_at      = timestamp()
      environment       = var.environment
    })
  }
}
