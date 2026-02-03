# Attic Stack - Backend Configuration
#
# Uses GitLab Managed Terraform State for state storage and locking.
# This enables collaboration and state versioning through GitLab.
#
# The HTTP backend configuration uses environment variables set by CI:
#   TF_HTTP_ADDRESS        - State read/write URL
#   TF_HTTP_LOCK_ADDRESS   - Lock URL
#   TF_HTTP_UNLOCK_ADDRESS - Unlock URL
#   TF_HTTP_USERNAME       - gitlab-ci-token
#   TF_HTTP_PASSWORD       - CI_JOB_TOKEN
#
# For local development, set these variables or use a local backend.

# NOTE: Using local backend for development
# Switch back to http backend for CI/CD
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# terraform {
#   backend "http" {
#     # Configuration is provided via environment variables in CI
#     # TF_HTTP_ADDRESS, TF_HTTP_LOCK_ADDRESS, etc.
#     #
#     # For local development, you can use:
#     #   tofu init -backend-config="address=..." -backend-config="lock_address=..."
#     #
#     # Or switch to local backend:
#     #   terraform {
#     #     backend "local" {
#     #       path = "terraform.tfstate"
#     #     }
#     #   }
#
#     retry_wait_min = 5
#   }
# }

# =============================================================================
# Alternative: Local Backend for Development
# =============================================================================
#
# Uncomment this and comment out the http backend above for local development:
#
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# =============================================================================
# Alternative: S3 Backend
# =============================================================================
#
# For teams not using GitLab, S3 backend with DynamoDB locking:
#
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state"
#     key            = "attic/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
