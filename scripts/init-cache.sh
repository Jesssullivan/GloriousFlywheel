#!/usr/bin/env bash
#
# init-cache.sh - Initialize Attic binary cache
#
# This script performs initial configuration of the Attic binary cache:
#   - Configures the Attic CLI
#   - Creates the main cache
#   - Extracts and displays public key for CI
#   - Verifies cache functionality
#
# Usage:
#   ./scripts/init-cache.sh [options]
#
# Options:
#   -e, --endpoint     Attic server URL (default: from ATTIC_SERVER env var)
#   -n, --name         Server name for CLI config (default: default)
#   -c, --cache        Cache name to create (default: main)
#   -p, --public       Make the cache public (default: true)
#   -t, --token        Attic authentication token (not needed for auth-free mode)
#   -k, --namespace    Kubernetes namespace for token retrieval (default: attic-cache)
#   --auth-free        Use auth-free mode (default)
#   --require-auth     Require authentication (override auth-free default)
#   -v, --verbose      Enable verbose output
#   -h, --help         Show this help message
#
# Prerequisites:
#   - attic CLI installed (nix shell nixpkgs#attic-client)
#   - For auth mode: Root or admin token with cache creation permissions
#
# Examples:
#   # Initialize with auth-free mode (default)
#   ./scripts/init-cache.sh -e https://attic-cache.example.com
#
#   # Initialize for production
#   ./scripts/init-cache.sh -e https://attic-cache.prod.example.com
#
#   # Initialize with authentication
#   ./scripts/init-cache.sh --require-auth -t 'eyJ...'

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
ENDPOINT="${ATTIC_SERVER:-https://attic-cache.example.com}"
SERVER_NAME="default"
CACHE_NAME="main"
MAKE_PUBLIC=true
TOKEN="${ATTIC_TOKEN:-}"
NAMESPACE="attic-cache"
VERBOSE=false
AUTH_FREE=true # Auth-free mode by default

# Colors
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m'
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

log_debug() {
  if $VERBOSE; then
    echo -e "${CYAN}[DEBUG]${NC} $*" >&2
  fi
}

# Usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Initialize Attic binary cache and configure CLI.

Options:
    -e, --endpoint     Attic server URL (default: $ENDPOINT)
    -n, --name         Server name for CLI config (default: $SERVER_NAME)
    -c, --cache        Cache name to create (default: $CACHE_NAME)
    -p, --public       Make the cache public (default: true)
    -t, --token        Attic authentication token (not needed for auth-free mode)
    -k, --namespace    Kubernetes namespace for token retrieval
    --auth-free        Use auth-free mode (default)
    --require-auth     Require authentication (override auth-free default)
    -v, --verbose      Enable verbose output
    -h, --help         Show this help message

Environment Variables:
    ATTIC_TOKEN        Authentication token (alternative to -t flag)

Examples:
    # Initialize with token from environment
    export ATTIC_TOKEN='eyJ...'
    $(basename "$0")

    # Create private cache with specific name
    $(basename "$0") -c private -p false

    # Retrieve token from Kubernetes
    $(basename "$0") -k nix-cache
EOF
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -e | --endpoint)
      ENDPOINT="$2"
      shift 2
      ;;
    -n | --name)
      SERVER_NAME="$2"
      shift 2
      ;;
    -c | --cache)
      CACHE_NAME="$2"
      shift 2
      ;;
    -p | --public)
      MAKE_PUBLIC="$2"
      shift 2
      ;;
    -t | --token)
      TOKEN="$2"
      shift 2
      ;;
    -k | --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    --auth-free)
      AUTH_FREE=true
      shift
      ;;
    --require-auth)
      AUTH_FREE=false
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
    esac
  done
}

# Check prerequisites
check_prerequisites() {
  local missing=()

  log_info "Checking prerequisites..."

  if ! command -v attic &>/dev/null; then
    missing+=("attic")
    log_warn "attic CLI not found"
    log_warn "Install with: nix shell nixpkgs#attic-client"
  fi

  if ! command -v curl &>/dev/null; then
    missing+=("curl")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    exit 1
  fi

  log_success "Prerequisites met"
}

# Retrieve token from Kubernetes
retrieve_token_from_k8s() {
  log_info "Retrieving token from Kubernetes..."

  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found, cannot retrieve token from Kubernetes"
    return 1
  fi

  # Try root token first
  local root_token
  root_token=$(kubectl get secret attic-root-token -n "$NAMESPACE" \
    -o jsonpath='{.data.root}' 2>/dev/null | base64 -d 2>/dev/null | jq -r '.secret' 2>/dev/null || echo "")

  if [[ -n $root_token ]]; then
    TOKEN="$root_token"
    log_success "Retrieved root token from Kubernetes"
    return 0
  fi

  # Try service token
  local service_token
  service_token=$(kubectl get secret attic-service-tokens -n "$NAMESPACE" \
    -o jsonpath='{.data.gc-worker}' 2>/dev/null | base64 -d 2>/dev/null | jq -r '.secret' 2>/dev/null || echo "")

  if [[ -n $service_token ]]; then
    TOKEN="$service_token"
    log_success "Retrieved service token from Kubernetes"
    return 0
  fi

  log_error "Could not retrieve token from Kubernetes secrets"
  log_error "Ensure attic-root-token or attic-service-tokens exists in namespace $NAMESPACE"
  return 1
}

# Validate token (skipped in auth-free mode)
validate_token() {
  if $AUTH_FREE; then
    log_info "Auth-free mode enabled - skipping token validation"
    return 0
  fi

  if [[ -z $TOKEN ]]; then
    log_warn "No token provided"

    # Try to get from Kubernetes
    if command -v kubectl &>/dev/null; then
      log_info "Attempting to retrieve token from Kubernetes..."
      if retrieve_token_from_k8s; then
        return 0
      fi
    fi

    log_error "No authentication token available"
    log_error "Provide via -t flag, ATTIC_TOKEN env var, or ensure kubectl access to secrets"
    log_error "Or use --auth-free for public caches"
    exit 1
  fi

  log_debug "Token length: ${#TOKEN} characters"
}

# Verify server connectivity
verify_server() {
  log_info "Verifying server connectivity..."

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$ENDPOINT/nix-cache-info" 2>/dev/null || echo "000")

  if [[ $http_code == "200" ]]; then
    log_success "Server is accessible at $ENDPOINT"
  else
    log_error "Cannot connect to server at $ENDPOINT (HTTP $http_code)"
    exit 1
  fi
}

# Configure Attic CLI
configure_cli() {
  log_info "Configuring Attic CLI..."

  # Create config directory
  local config_dir="$HOME/.config/attic"
  mkdir -p "$config_dir"

  # Login to server
  log_info "Logging in to $SERVER_NAME..."

  if $AUTH_FREE; then
    # Auth-free mode: login without token (anonymous access)
    if ! attic login "$SERVER_NAME" "$ENDPOINT"; then
      log_warn "Login command failed - this may be expected for auth-free servers"
      log_info "Attempting to configure manually..."
      # Create config directly for auth-free access
      cat >"$config_dir/config.toml" <<EOF
default-server = "$SERVER_NAME"

[servers.$SERVER_NAME]
endpoint = "$ENDPOINT"
EOF
      log_success "Attic CLI configured manually for auth-free access"
    else
      log_success "Attic CLI configured for $SERVER_NAME"
    fi
  else
    # Authenticated mode: login with token
    if ! attic login "$SERVER_NAME" "$ENDPOINT" "$TOKEN"; then
      log_error "Failed to login to Attic server"
      exit 1
    fi
    log_success "Attic CLI configured for $SERVER_NAME"
  fi

  # Show current configuration
  log_debug "Attic config location: $config_dir/config.toml"
}

# Create cache
create_cache() {
  log_info "Creating cache: $CACHE_NAME..."

  local cache_args=()

  if [[ $MAKE_PUBLIC == "true" ]]; then
    cache_args+=("--public")
    log_info "Cache will be public"
  else
    log_info "Cache will be private"
  fi

  # Check if cache already exists
  if attic cache info "$SERVER_NAME:$CACHE_NAME" &>/dev/null; then
    log_warn "Cache $CACHE_NAME already exists"
  else
    if ! attic cache create "$SERVER_NAME:$CACHE_NAME" "${cache_args[@]}"; then
      log_error "Failed to create cache $CACHE_NAME"
      exit 1
    fi
    log_success "Cache $CACHE_NAME created"
  fi
}

# Get cache info and public key
get_cache_info() {
  log_info "Retrieving cache information..."

  local cache_info
  cache_info=$(attic cache info "$SERVER_NAME:$CACHE_NAME" 2>&1 || echo "")

  if [[ -z $cache_info ]]; then
    log_error "Could not retrieve cache info"
    return 1
  fi

  echo ""
  echo "=========================================="
  echo "Cache Information"
  echo "=========================================="
  echo ""
  echo "$cache_info"
  echo ""

  # Extract public key
  local public_key
  public_key=$(echo "$cache_info" | grep -E "^Public Key:" | cut -d':' -f2- | xargs || echo "")

  if [[ -n $public_key ]]; then
    echo "=========================================="
    echo "Public Key (for nix.conf)"
    echo "=========================================="
    echo ""
    echo "Add to your nix.conf or flake.nix:"
    echo ""
    echo "  extra-substituters = $ENDPOINT"
    echo "  extra-trusted-public-keys = $public_key"
    echo ""

    # Save to file
    local key_file="$REPO_ROOT/public-key.txt"
    echo "$public_key" >"$key_file"
    log_info "Public key saved to: $key_file"
  fi
}

# Test cache functionality
test_cache() {
  log_info "Testing cache functionality..."

  # Try to query the cache
  local test_result
  test_result=$(attic cache info "$SERVER_NAME:$CACHE_NAME" 2>&1 || echo "FAILED")

  if [[ $test_result != *"FAILED"* ]]; then
    log_success "Cache is functional"
  else
    log_warn "Cache query returned unexpected result"
    log_debug "Result: $test_result"
  fi

  # Verify nix-cache-info
  local cache_info_response
  cache_info_response=$(curl -s "$ENDPOINT/nix-cache-info" 2>/dev/null || echo "")

  if [[ -n $cache_info_response ]]; then
    log_debug "nix-cache-info: $cache_info_response"

    local store_dir
    store_dir=$(echo "$cache_info_response" | grep "StoreDir:" | cut -d':' -f2 | xargs || echo "")
    local want_mass_query
    want_mass_query=$(echo "$cache_info_response" | grep "WantMassQuery:" | cut -d':' -f2 | xargs || echo "")
    local priority
    priority=$(echo "$cache_info_response" | grep "Priority:" | cut -d':' -f2 | xargs || echo "")

    log_info "Store directory: ${store_dir:-/nix/store}"
    log_info "Mass query: ${want_mass_query:-1}"
    log_info "Priority: ${priority:-40}"
  fi
}

# Print CI configuration
print_ci_config() {
  echo ""
  echo "=========================================="
  echo "CI Configuration"
  echo "=========================================="
  echo ""
  echo "GitLab CI Variables:"
  echo "  ATTIC_SERVER: $ENDPOINT"
  echo "  ATTIC_CACHE: $CACHE_NAME"
  echo "  ATTIC_TOKEN: (retrieve from Kubernetes secret)"
  echo ""
  echo "Example .gitlab-ci.yml:"
  echo ""
  cat <<EOF
nix:build:
  script:
    - nix develop -c attic login tinyland \$ATTIC_SERVER \$ATTIC_TOKEN
    - nix build .#package
    - attic push tinyland:\$ATTIC_CACHE result
EOF
  echo ""
  echo "Example flake.nix nixConfig:"
  echo ""
  cat <<EOF
{
  nixConfig = {
    extra-substituters = ["$ENDPOINT"];
    extra-trusted-public-keys = ["<public-key-from-above>"];
  };
}
EOF
  echo ""
}

# Generate Kubernetes secret for CI
generate_ci_secret() {
  local ci_token_name="${1:-gitlab-ci}"

  log_info "CI configuration..."

  echo ""
  echo "Note: Auth-free mode - no CI tokens required."
  echo "Configure the following GitLab CI/CD variables:"
  echo ""
  echo "  When using external S3 (use_minio=false):"
  echo "    S3_ENDPOINT           - S3 endpoint URL"
  echo "    S3_ACCESS_KEY_ID      - S3 access key (masked)"
  echo "    S3_SECRET_ACCESS_KEY  - S3 secret key (masked)"
  echo "    S3_BUCKET_NAME        - S3 bucket name"
  echo ""
  echo "  When using MinIO (use_minio=true, default):"
  echo "    No S3 variables required - MinIO provides storage internally."
  echo ""
}

# Main execution
main() {
  parse_args "$@"

  echo ""
  log_info "Attic Cache Initialization"
  log_info "=========================="
  log_info "Server: $ENDPOINT"
  log_info "Cache: $CACHE_NAME"
  echo ""

  check_prerequisites
  validate_token
  verify_server
  configure_cli
  create_cache
  get_cache_info
  test_cache
  print_ci_config

  echo ""
  log_success "Cache initialization complete!"
  echo ""
  log_info "Next steps:"
  echo "  1. Add the public key to your nix.conf or flake.nix"
  if $AUTH_FREE; then
    echo "  2. Push derivations: attic push $SERVER_NAME:$CACHE_NAME ./result"
    echo ""
    echo "  Note: Auth-free mode - no ATTIC_TOKEN needed for CI"
  else
    echo "  2. Configure CI with ATTIC_SERVER and ATTIC_TOKEN variables"
    echo "  3. Push your first derivation: attic push $SERVER_NAME:$CACHE_NAME ./result"
  fi
  echo ""
}

main "$@"
