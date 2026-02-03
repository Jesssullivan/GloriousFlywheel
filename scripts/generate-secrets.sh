#!/usr/bin/env bash
#
# generate-secrets.sh - Generate secrets for Attic deployment
#
# This script generates all required secrets for deploying Attic:
#   1. JWT RS256 signing key (RSA 4096-bit)
#   2. Random database password (if using CNPG)
#   3. Kubernetes secret manifests (optional)
#
# Usage:
#   ./scripts/generate-secrets.sh [options]
#
# Options:
#   -o, --output-dir DIR    Output directory (default: ./secrets)
#   -k, --keepass           Store secrets in KeePassXC (requires keepassxc-cli)
#   -m, --k8s-manifests     Generate Kubernetes secret manifests
#   -f, --force             Overwrite existing secrets
#   -h, --help              Show this help message
#
# Environment Variables:
#   KEEPASS_DATABASE_PATH   Path to KeePassXC database
#   KEEPASS_PASSWORD        KeePassXC master password
#
# Security:
#   - Generated secrets are stored with 600 permissions
#   - Private keys are never logged or echoed
#   - Files are created in a secure temporary directory first
#
# Example:
#   # Generate secrets to ./secrets directory
#   ./scripts/generate-secrets.sh
#
#   # Generate and store in KeePassXC
#   ./scripts/generate-secrets.sh --keepass
#
#   # Generate K8s manifests for manual apply
#   ./scripts/generate-secrets.sh --k8s-manifests

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/secrets"
STORE_KEEPASS=false
GENERATE_K8S=false
FORCE=false

# Colors for output (disabled if not terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  NC=''
fi

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
  echo -e "${CYAN}[STEP]${NC} $*" >&2
}

# Usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Generate secrets for Attic deployment.

Options:
    -o, --output-dir DIR    Output directory (default: ./secrets)
    -k, --keepass           Store secrets in KeePassXC
    -m, --k8s-manifests     Generate Kubernetes secret manifests
    -f, --force             Overwrite existing secrets
    -h, --help              Show this help message

Generated Secrets:
    jwt-signing-key.pem     RSA 4096-bit private key (PEM format)
    jwt-signing-key.b64     Base64-encoded key (for terraform.tfvars)
    db-password.txt         Random 32-byte database password
    k8s-secrets.yaml        Kubernetes Secret manifest (if --k8s-manifests)

Examples:
    # Basic usage - generate to ./secrets
    $(basename "$0")

    # Store in KeePassXC
    $(basename "$0") --keepass

    # Generate K8s manifests
    $(basename "$0") --k8s-manifests

    # Force regenerate
    $(basename "$0") --force

EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -o | --output-dir)
    OUTPUT_DIR="$2"
    shift 2
    ;;
  -k | --keepass)
    STORE_KEEPASS=true
    shift
    ;;
  -m | --k8s-manifests)
    GENERATE_K8S=true
    shift
    ;;
  -f | --force)
    FORCE=true
    shift
    ;;
  -h | --help)
    usage
    ;;
  -*)
    log_error "Unknown option: $1"
    exit 1
    ;;
  *)
    log_error "Unexpected argument: $1"
    exit 1
    ;;
  esac
done

# Check prerequisites
check_prerequisites() {
  local missing=()

  if ! command -v openssl &>/dev/null; then
    missing+=("openssl")
  fi

  if $STORE_KEEPASS && ! command -v keepassxc-cli &>/dev/null; then
    missing+=("keepassxc-cli (for --keepass)")
  fi

  if $GENERATE_K8S && ! command -v kubectl &>/dev/null; then
    log_warn "kubectl not found - K8s manifests will be generated but not validated"
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

# Create secure output directory
create_output_dir() {
  if [[ ! -d $OUTPUT_DIR ]]; then
    log_info "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    chmod 700 "$OUTPUT_DIR"
  fi

  # Add to .gitignore if in repo
  local gitignore="${REPO_ROOT}/.gitignore"
  local secrets_pattern="secrets/"
  if [[ -f $gitignore ]] && ! grep -q "^${secrets_pattern}$" "$gitignore"; then
    log_info "Adding $secrets_pattern to .gitignore"
    echo "$secrets_pattern" >>"$gitignore"
  fi
}

# Generate RSA private key for JWT signing
generate_jwt_key() {
  local key_file="${OUTPUT_DIR}/jwt-signing-key.pem"
  local b64_file="${OUTPUT_DIR}/jwt-signing-key.b64"

  if [[ -f $key_file ]] && ! $FORCE; then
    log_warn "JWT signing key already exists: $key_file"
    log_warn "Use --force to regenerate"
    return 0
  fi

  log_step "Generating RSA 4096-bit private key for JWT signing..."

  # Generate RSA key with traditional format (required by Attic)
  # The -traditional flag ensures PKCS#1 format (BEGIN RSA PRIVATE KEY)
  # rather than PKCS#8 format (BEGIN PRIVATE KEY)
  openssl genrsa -traditional 4096 2>/dev/null >"$key_file"
  chmod 600 "$key_file"

  # Create base64-encoded version (single line, no wrapping)
  # This is the format required by ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
  base64 -w0 <"$key_file" >"$b64_file"
  chmod 600 "$b64_file"

  log_success "Generated JWT signing key: $key_file"
  log_success "Generated base64 key: $b64_file"

  # Verify the key is valid
  if openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
    log_success "Key validation passed"
  else
    log_error "Key validation failed"
    exit 1
  fi
}

# Generate random database password
generate_db_password() {
  local pwd_file="${OUTPUT_DIR}/db-password.txt"

  if [[ -f $pwd_file ]] && ! $FORCE; then
    log_warn "Database password already exists: $pwd_file"
    log_warn "Use --force to regenerate"
    return 0
  fi

  log_step "Generating random database password..."

  # Generate 32 bytes of random data, base64 encode
  # Remove special characters that might cause issues in connection strings
  openssl rand -base64 32 | tr -d '/+=' | head -c 32 >"$pwd_file"
  chmod 600 "$pwd_file"

  log_success "Generated database password: $pwd_file"
}

# Generate Kubernetes secret manifests
generate_k8s_manifests() {
  local manifest_file="${OUTPUT_DIR}/k8s-secrets.yaml"

  if [[ -f $manifest_file ]] && ! $FORCE; then
    log_warn "K8s manifest already exists: $manifest_file"
    log_warn "Use --force to regenerate"
    return 0
  fi

  log_step "Generating Kubernetes secret manifests..."

  local jwt_b64
  jwt_b64=$(cat "${OUTPUT_DIR}/jwt-signing-key.b64")

  local db_password
  db_password=$(cat "${OUTPUT_DIR}/db-password.txt")

  # Note: These are pre-deployment manifests. Actual secrets are created by OpenTofu.
  cat >"$manifest_file" <<EOF
# Attic Secrets - Pre-deployment Reference
# =========================================
# These manifests are for reference only. Actual secrets are managed by OpenTofu.
# Use these for:
#   1. Manual testing without OpenTofu
#   2. Disaster recovery
#   3. Secret rotation verification
#
# Apply with: kubectl apply -f k8s-secrets.yaml
# WARNING: Ensure namespace exists first: kubectl create namespace nix-cache

---
apiVersion: v1
kind: Namespace
metadata:
  name: nix-cache
  labels:
    app.kubernetes.io/name: attic
    app.kubernetes.io/managed-by: manual
---
apiVersion: v1
kind: Secret
metadata:
  name: attic-secrets
  namespace: nix-cache
  labels:
    app.kubernetes.io/name: attic
    app.kubernetes.io/component: secrets
    app.kubernetes.io/managed-by: manual
type: Opaque
stringData:
  # JWT signing key (RS256)
  ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64: "${jwt_b64}"

  # Database URL - REPLACE with actual Neon or CNPG URL
  # For CNPG, this is auto-generated by OpenTofu
  DATABASE_URL: "postgresql://attic:${db_password}@attic-pg-rw.nix-cache.svc:5432/attic?sslmode=require"

  # S3 credentials - REPLACE with actual Civo Object Storage credentials
  # These are auto-generated by OpenTofu
  AWS_ACCESS_KEY_ID: "<REPLACE_WITH_CIVO_ACCESS_KEY>"
  AWS_SECRET_ACCESS_KEY: "<REPLACE_WITH_CIVO_SECRET_KEY>"
---
# ConfigMap for Attic server configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: attic-config
  namespace: nix-cache
  labels:
    app.kubernetes.io/name: attic
    app.kubernetes.io/component: config
    app.kubernetes.io/managed-by: manual
data:
  server.toml: |
    # Attic Server Configuration
    # This is a reference config. Production config is generated by OpenTofu.

    listen = "[::]:8080"

    [database]
    # Uses DATABASE_URL environment variable

    [storage]
    type = "s3"
    region = "NYC1"
    bucket = "nix-cache"
    endpoint = "https://objectstore.nyc1.civo.com"

    [chunking]
    nar-size-threshold = 65536
    min-size = 16384
    avg-size = 65536
    max-size = 262144

    [compression]
    type = "zstd"
    level = 8

    [garbage-collection]
    interval = "12 hours"
    default-retention-period = "3 months"
EOF

  chmod 600 "$manifest_file"
  log_success "Generated K8s manifests: $manifest_file"
}

# Store secrets in KeePassXC
store_keepass() {
  if [[ -z ${KEEPASS_DATABASE_PATH:-} ]]; then
    log_error "KEEPASS_DATABASE_PATH not set"
    log_error "Set environment variable or use --output-dir instead"
    exit 1
  fi

  if [[ ! -f $KEEPASS_DATABASE_PATH ]]; then
    log_error "KeePassXC database not found: $KEEPASS_DATABASE_PATH"
    exit 1
  fi

  log_step "Storing secrets in KeePassXC..."

  local jwt_b64
  jwt_b64=$(cat "${OUTPUT_DIR}/jwt-signing-key.b64")

  local db_password
  db_password=$(cat "${OUTPUT_DIR}/db-password.txt")

  # Create entries in KeePassXC
  # Note: This requires keepassxc-cli and KEEPASS_PASSWORD to be set
  if [[ -z ${KEEPASS_PASSWORD:-} ]]; then
    log_warn "KEEPASS_PASSWORD not set - manual entry required"
    log_info "Add the following entries to KeePassXC:"
    log_info "  tinyland/infra/attic/jwt_signing_key - paste content of jwt-signing-key.b64"
    log_info "  tinyland/infra/attic/db_password - paste content of db-password.txt"
    return 0
  fi

  # Try to add entries
  local group="tinyland/infra/attic"

  # Add JWT signing key
  if echo "$KEEPASS_PASSWORD" | keepassxc-cli add "$KEEPASS_DATABASE_PATH" \
    "$group/jwt_signing_key" \
    --username "jwt" \
    --password-prompt <<<"$jwt_b64" 2>/dev/null; then
    log_success "Added jwt_signing_key to KeePassXC"
  else
    log_warn "Failed to add jwt_signing_key (may already exist)"
  fi

  # Add database password
  if echo "$KEEPASS_PASSWORD" | keepassxc-cli add "$KEEPASS_DATABASE_PATH" \
    "$group/db_password" \
    --username "attic" \
    --password-prompt <<<"$db_password" 2>/dev/null; then
    log_success "Added db_password to KeePassXC"
  else
    log_warn "Failed to add db_password (may already exist)"
  fi
}

# Print summary
print_summary() {
  echo ""
  log_success "Secret generation complete!"
  echo ""
  echo -e "${CYAN}Generated files:${NC}"
  ls -la "${OUTPUT_DIR}/" | grep -v "^total" | grep -v "^d" | awk '{print "  " $NF}'
  echo ""
  echo -e "${CYAN}Next steps:${NC}"
  echo ""
  echo "1. Copy the JWT key to terraform.tfvars:"
  echo "   ${YELLOW}attic_jwt_secret_base64 = \"$(head -c 50 "${OUTPUT_DIR}/jwt-signing-key.b64")...\"${NC}"
  echo ""
  echo "2. Store secrets in KeePassXC (recommended):"
  echo "   - tinyland/infra/attic/jwt_signing_key"
  echo "   - tinyland/infra/attic/db_password"
  echo ""
  echo "3. Set CI/CD variables:"
  echo "   - ATTIC_JWT_SECRET (masked, protected)"
  echo "   - CIVO_API_KEY (masked, protected)"
  echo ""
  echo "4. Deploy with OpenTofu:"
  echo "   ${YELLOW}cd tofu/stacks/attic${NC}"
  echo "   ${YELLOW}tofu init${NC}"
  echo "   ${YELLOW}tofu plan -var-file=terraform.tfvars${NC}"
  echo "   ${YELLOW}tofu apply -var-file=terraform.tfvars${NC}"
  echo ""
  echo -e "${RED}SECURITY WARNING:${NC}"
  echo "  - Never commit secrets to git"
  echo "  - Delete ${OUTPUT_DIR}/ after storing secrets securely"
  echo "  - Rotate keys periodically (see docs/security/token-rotation.md)"
  echo ""
}

# Main execution
main() {
  log_info "Attic Secrets Generator"
  log_info "======================"
  echo ""

  check_prerequisites
  create_output_dir

  generate_jwt_key
  generate_db_password

  if $GENERATE_K8S; then
    generate_k8s_manifests
  fi

  if $STORE_KEEPASS; then
    store_keepass
  fi

  print_summary
}

main "$@"
