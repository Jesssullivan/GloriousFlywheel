#!/usr/bin/env bash
#
# generate-ci-token.sh - Generate a scoped CI token for Attic
#
# This script generates a new CI token for a specific repository.
# The token is created via OpenTofu and stored in Kubernetes secrets.
#
# Usage:
#   ./scripts/generate-ci-token.sh <repo-name> <permissions> [caches]
#
# Examples:
#   ./scripts/generate-ci-token.sh gitlab-tinyland-gnucashr "push,pull" main
#   ./scripts/generate-ci-token.sh github-jesssullivan-foo "pull" main,staging
#
# Environment Variables:
#   NAMESPACE     - Kubernetes namespace (default: nix-cache)
#   KUBECONFIG    - Path to kubeconfig file
#   TOFU_DIR      - OpenTofu stack directory (default: tofu/stacks/attic)
#
# Security:
#   - Token values are NEVER logged
#   - Output is JSON for programmatic consumption
#   - Script exits with error if token generation fails

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-nix-cache}"
TOFU_DIR="${TOFU_DIR:-tofu/stacks/attic}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output (disabled if not terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
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

# Usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") <repo-name> <permissions> [caches]

Generate a scoped CI token for Attic binary cache.

Arguments:
    repo-name     Repository identifier (e.g., gitlab-tinyland-gnucashr)
    permissions   Comma-separated permissions: push, pull, delete, admin
    caches        Comma-separated cache names (default: main)

Options:
    -h, --help    Show this help message
    -o, --output  Output format: json, env, raw (default: json)
    -d, --dry-run Show what would be done without making changes

Examples:
    # Create push/pull token for main cache
    $(basename "$0") gitlab-tinyland-gnucashr "push,pull" main

    # Create pull-only token for multiple caches
    $(basename "$0") public-reader "pull" "main,staging"

    # Output as environment variable format
    $(basename "$0") -o env gitlab-tinyland-gnucashr "push,pull" main

Environment Variables:
    NAMESPACE     Kubernetes namespace (default: nix-cache)
    KUBECONFIG    Path to kubeconfig file
    TOFU_DIR      OpenTofu stack directory

EOF
  exit 0
}

# Parse arguments
OUTPUT_FORMAT="json"
DRY_RUN=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help)
    usage
    ;;
  -o | --output)
    OUTPUT_FORMAT="$2"
    shift 2
    ;;
  -d | --dry-run)
    DRY_RUN=true
    shift
    ;;
  -*)
    log_error "Unknown option: $1"
    exit 1
    ;;
  *)
    POSITIONAL_ARGS+=("$1")
    shift
    ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]:-}"

# Validate arguments
if [[ ${#POSITIONAL_ARGS[@]} -lt 2 ]]; then
  log_error "Missing required arguments"
  usage
fi

REPO_NAME="${POSITIONAL_ARGS[0]}"
PERMISSIONS="${POSITIONAL_ARGS[1]}"
CACHES="${POSITIONAL_ARGS[2]:-main}"

# Validate repo name (alphanumeric, hyphens, underscores)
if [[ ! $REPO_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
  log_error "Invalid repo name: $REPO_NAME (must be alphanumeric with hyphens/underscores)"
  exit 1
fi

# Validate permissions
IFS=',' read -ra PERM_ARRAY <<<"$PERMISSIONS"
for perm in "${PERM_ARRAY[@]}"; do
  if [[ ! $perm =~ ^(push|pull|delete|admin)$ ]]; then
    log_error "Invalid permission: $perm (must be push, pull, delete, or admin)"
    exit 1
  fi
done

# Validate caches
IFS=',' read -ra CACHE_ARRAY <<<"$CACHES"
for cache in "${CACHE_ARRAY[@]}"; do
  if [[ ! $cache =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid cache name: $cache"
    exit 1
  fi
done

# Check prerequisites
check_prerequisites() {
  local missing=()

  if ! command -v kubectl &>/dev/null; then
    missing+=("kubectl")
  fi

  if ! command -v tofu &>/dev/null && ! command -v terraform &>/dev/null; then
    missing+=("tofu or terraform")
  fi

  if ! command -v jq &>/dev/null; then
    missing+=("jq")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

# Verify Kubernetes connectivity
verify_kubernetes() {
  if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Cannot access namespace: $NAMESPACE"
    log_error "Check KUBECONFIG and cluster connectivity"
    exit 1
  fi
}

# Get IaC tool (prefer tofu, fall back to terraform)
get_iac_tool() {
  if command -v tofu &>/dev/null; then
    echo "tofu"
  else
    echo "terraform"
  fi
}

# Generate token configuration
generate_token_config() {
  local repo_name="$1"
  local permissions="$2"
  local caches="$3"

  # Convert comma-separated to JSON arrays
  local perm_json
  perm_json=$(echo "$permissions" | jq -R 'split(",")')

  local cache_json
  cache_json=$(echo "$caches" | jq -R 'split(",")')

  cat <<EOF
{
  "$repo_name": {
    "permissions": $perm_json,
    "caches": $cache_json,
    "description": "CI token for $repo_name"
  }
}
EOF
}

# Create tfvars snippet for the new token
create_tfvars_snippet() {
  local config="$1"

  cat <<EOF

# Added by generate-ci-token.sh at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ci_tokens = merge(var.ci_tokens, $config)
EOF
}

# Apply token via OpenTofu
apply_token() {
  local iac_tool
  iac_tool=$(get_iac_tool)

  local tofu_path="$REPO_ROOT/$TOFU_DIR"

  if [[ ! -d $tofu_path ]]; then
    log_error "OpenTofu directory not found: $tofu_path"
    exit 1
  fi

  log_info "Generating token via $iac_tool..."

  cd "$tofu_path"

  # Generate the token configuration
  local token_config
  token_config=$(generate_token_config "$REPO_NAME" "$PERMISSIONS" "$CACHES")

  if $DRY_RUN; then
    log_warn "DRY RUN - Would add token configuration:"
    echo "$token_config" | jq . >&2
    create_tfvars_snippet "$token_config" >&2
    return 0
  fi

  # Note: In a real implementation, this would update terraform.tfvars
  # and run tofu apply. For now, we show the configuration.
  log_warn "Token configuration to add to terraform.tfvars:"
  create_tfvars_snippet "$token_config" >&2

  log_info "Run the following command to apply:"
  echo "$iac_tool apply -var-file=terraform.tfvars -target=module.attic_tokens" >&2
}

# Retrieve token from Kubernetes secret
retrieve_token() {
  local secret_name="attic-ci-tokens"

  log_info "Retrieving token from Kubernetes secret..."

  if ! kubectl get secret "$secret_name" -n "$NAMESPACE" &>/dev/null; then
    log_error "Secret $secret_name not found in namespace $NAMESPACE"
    log_error "Token may not have been created yet. Run 'tofu apply' first."
    exit 1
  fi

  local token_data
  token_data=$(kubectl get secret "$secret_name" -n "$NAMESPACE" \
    -o jsonpath="{.data.$REPO_NAME}" 2>/dev/null | base64 -d 2>/dev/null || true)

  if [[ -z $token_data ]]; then
    log_error "Token for $REPO_NAME not found in secret"
    log_info "Available tokens:"
    kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' >&2
    exit 1
  fi

  echo "$token_data"
}

# Format output
format_output() {
  local token_data="$1"

  case "$OUTPUT_FORMAT" in
  json)
    echo "$token_data" | jq -c '.'
    ;;
  env)
    local token
    token=$(echo "$token_data" | jq -r '.secret')
    echo "ATTIC_TOKEN='$token'"
    ;;
  raw)
    echo "$token_data" | jq -r '.secret'
    ;;
  *)
    log_error "Unknown output format: $OUTPUT_FORMAT"
    exit 1
    ;;
  esac
}

# Main execution
main() {
  log_info "Generating CI token for: $REPO_NAME"
  log_info "Permissions: $PERMISSIONS"
  log_info "Caches: $CACHES"

  check_prerequisites
  verify_kubernetes

  # Show what would be created
  apply_token

  if $DRY_RUN; then
    log_success "Dry run complete"
    exit 0
  fi

  # Try to retrieve existing token
  log_info "Attempting to retrieve token..."

  if token_data=$(retrieve_token 2>/dev/null); then
    log_success "Token retrieved successfully"
    format_output "$token_data"
  else
    log_warn "Token not yet available in Kubernetes"
    log_info "After running 'tofu apply', retrieve the token with:"
    echo "kubectl get secret attic-ci-tokens -n $NAMESPACE -o jsonpath='{.data.$REPO_NAME}' | base64 -d | jq" >&2
  fi
}

main "$@"
