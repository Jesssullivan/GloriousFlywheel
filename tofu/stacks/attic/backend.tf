# Attic Stack - Backend Configuration
#
# Uses GitLab Managed Terraform State for state storage and locking.
# This enables collaboration and state versioning through GitLab.
#
# Backend Configuration Methods:
#
# 1. CI/CD (automatic):
#    Environment variables are set by .gitlab-ci.yml templates:
#      TF_HTTP_ADDRESS, TF_HTTP_LOCK_ADDRESS, TF_HTTP_UNLOCK_ADDRESS
#      TF_HTTP_USERNAME (gitlab-ci-token), TF_HTTP_PASSWORD (CI_JOB_TOKEN)
#
# 2. Local development with GitLab state:
#    Use Justfile commands which configure backend via -backend-config:
#      just init          # Initialize with GitLab backend
#      just plan          # Plan changes
#      just apply         # Apply changes
#
#    Or manually:
#      export TF_HTTP_PASSWORD="glpat-your-token"
#      tofu init -backend-config=backend.local.hcl
#
# 3. Local-only state (not recommended for shared infrastructure):
#    tofu init -backend=false
#    # Uses in-memory state, changes are not persisted

terraform {
  # HTTP backend for GitLab Managed Terraform State
  # All configuration provided via environment variables or -backend-config
  backend "http" {
    # Required TF_HTTP_* environment variables:
    #   TF_HTTP_ADDRESS        - State read/write URL
    #   TF_HTTP_LOCK_ADDRESS   - Lock URL
    #   TF_HTTP_UNLOCK_ADDRESS - Unlock URL
    #   TF_HTTP_USERNAME       - GitLab username or "gitlab-ci-token"
    #   TF_HTTP_PASSWORD       - Personal access token or CI_JOB_TOKEN
    #
    # Optional:
    #   TF_HTTP_LOCK_METHOD    - POST (default)
    #   TF_HTTP_UNLOCK_METHOD  - DELETE (default)
    #   TF_HTTP_RETRY_WAIT_MIN - Retry wait time (default: 1s)
  }
}
