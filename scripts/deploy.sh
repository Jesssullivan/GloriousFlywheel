#!/usr/bin/env bash
#
# deploy.sh - Deploy Attic binary cache infrastructure
#
# This script performs a complete deployment of the Attic binary cache
# infrastructure to Civo Kubernetes using OpenTofu.
#
# Usage:
#   ./scripts/deploy.sh [options]
#
# Options:
#   -e, --environment  Environment: production, staging, development (default: production)
#   -n, --namespace    Kubernetes namespace (default: nix-cache)
#   -d, --dry-run      Show what would be done without making changes
#   -f, --force        Skip confirmation prompts
#   -t, --targets      Comma-separated Tofu targets (e.g., "module.attic_api,module.object_storage")
#   -v, --verbose      Enable verbose output
#   -h, --help         Show this help message
#
# Prerequisites:
#   - kubectl configured with Civo cluster access
#   - tofu (OpenTofu) or terraform installed
#   - Civo API key configured
#   - JWT signing key generated
#
# Environment Variables:
#   CIVO_API_KEY           - Civo API key (required)
#   ATTIC_JWT_SECRET       - Base64-encoded RSA key for JWT signing
#   TF_HTTP_ADDRESS        - GitLab Terraform state URL (for remote state)
#   KUBECONFIG             - Path to kubeconfig file
#
# Examples:
#   # Production deployment
#   ./scripts/deploy.sh
#
#   # Staging deployment with dry-run
#   ./scripts/deploy.sh -e staging -d
#
#   # Deploy only the API module
#   ./scripts/deploy.sh -t module.attic_api

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOFU_DIR="$REPO_ROOT/tofu/stacks/attic"

# Default values
ENVIRONMENT="production"
NAMESPACE="nix-cache"
DRY_RUN=false
FORCE=false
TARGETS=""
VERBOSE=false

# Colors for output (disabled if not terminal)
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

Deploy Attic binary cache infrastructure to Civo Kubernetes.

Options:
    -e, --environment  Environment: production, staging, development (default: production)
    -n, --namespace    Kubernetes namespace (default: nix-cache)
    -d, --dry-run      Show what would be done without making changes
    -f, --force        Skip confirmation prompts
    -t, --targets      Comma-separated Tofu targets
    -v, --verbose      Enable verbose output
    -h, --help         Show this help message

Environment Variables:
    CIVO_API_KEY           Civo API key (required)
    ATTIC_JWT_SECRET       Base64-encoded RSA key for JWT signing
    KUBECONFIG             Path to kubeconfig file

Examples:
    # Production deployment
    $(basename "$0")

    # Staging with dry-run
    $(basename "$0") -e staging -d

    # Deploy specific module
    $(basename "$0") -t module.attic_api
EOF
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -e | --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -n | --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -d | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -f | --force)
      FORCE=true
      shift
      ;;
    -t | --targets)
      TARGETS="$2"
      shift 2
      ;;
    -v | --verbose)
      VERBOSE=true
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

# Validate environment
validate_environment() {
  case "$ENVIRONMENT" in
  production | staging | development)
    log_info "Environment: $ENVIRONMENT"
    ;;
  *)
    log_error "Invalid environment: $ENVIRONMENT"
    log_error "Must be one of: production, staging, development"
    exit 1
    ;;
  esac
}

# Check prerequisites
check_prerequisites() {
  local missing=()

  log_info "Checking prerequisites..."

  # Check kubectl
  if ! command -v kubectl &>/dev/null; then
    missing+=("kubectl")
  fi

  # Check tofu/terraform
  if ! command -v tofu &>/dev/null && ! command -v terraform &>/dev/null; then
    missing+=("tofu or terraform")
  fi

  # Check jq
  if ! command -v jq &>/dev/null; then
    missing+=("jq")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    log_error "Please install the missing tools and try again."
    exit 1
  fi

  log_success "All required tools are installed"
}

# Validate environment variables
validate_env_vars() {
  local missing=()

  log_info "Validating environment variables..."

  if [[ -z ${CIVO_API_KEY:-} ]]; then
    missing+=("CIVO_API_KEY")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required environment variables: ${missing[*]}"
    log_error ""
    log_error "Set them via:"
    for var in "${missing[@]}"; do
      log_error "  export $var='...'"
    done
    exit 1
  fi

  log_success "Environment variables validated"
}

# Verify Kubernetes connectivity
verify_kubernetes() {
  log_info "Verifying Kubernetes connectivity..."

  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    log_error "Check KUBECONFIG or cluster configuration"
    exit 1
  fi

  local context
  context=$(kubectl config current-context 2>/dev/null || echo "unknown")
  log_info "Current Kubernetes context: $context"

  # Verify we're on the correct cluster
  if [[ $context != *"civo"* && $context != *"bitter-darkness"* ]]; then
    log_warn "Current context doesn't appear to be the Civo cluster"
    log_warn "Context: $context"
    if ! $FORCE; then
      read -rp "Continue anyway? (y/N) " confirm
      if [[ $confirm != "y" && $confirm != "Y" ]]; then
        log_error "Deployment cancelled"
        exit 1
      fi
    fi
  fi

  log_success "Kubernetes connectivity verified"
}

# Get IaC tool (prefer tofu, fall back to terraform)
get_iac_tool() {
  if command -v tofu &>/dev/null; then
    echo "tofu"
  else
    echo "terraform"
  fi
}

# Initialize OpenTofu
init_tofu() {
  local iac_tool
  iac_tool=$(get_iac_tool)

  log_info "Initializing $iac_tool..."

  cd "$TOFU_DIR"

  local init_args=()
  if $DRY_RUN; then
    init_args+=("-input=false")
  fi

  # Check for remote state configuration
  if [[ -n ${TF_HTTP_ADDRESS:-} ]]; then
    log_info "Using remote state backend (GitLab)"
  else
    log_warn "No remote state configured, using local state"
    log_warn "Set TF_HTTP_ADDRESS for team collaboration"
  fi

  if ! $iac_tool init "${init_args[@]}"; then
    log_error "Failed to initialize $iac_tool"
    exit 1
  fi

  log_success "$iac_tool initialized"
}

# Generate tfvars file if needed
prepare_tfvars() {
  local tfvars_file="$TOFU_DIR/terraform.tfvars"

  if [[ ! -f $tfvars_file ]]; then
    log_warn "No terraform.tfvars found"
    log_info "Creating minimal tfvars file..."

    cat >"$tfvars_file" <<EOF
# Attic Stack Configuration
# Generated by deploy.sh at $(date -u +"%Y-%m-%dT%H:%M:%SZ")

environment = "$ENVIRONMENT"
namespace   = "$NAMESPACE"

# Civo Configuration (API key via CIVO_API_KEY env var or TF_VAR_civo_api_key)
civo_region = "NYC1"

# Ingress
enable_ingress = true
ingress_host   = "nix-cache.fuzzy-dev.tinyland.dev"
enable_tls     = true

# API Server
api_min_replicas = 2
api_max_replicas = 10

# PostgreSQL (CloudNativePG)
use_cnpg_postgres = true
pg_instances      = 3
pg_storage_size   = "10Gi"
pg_enable_backup  = true

# JWT secret must be provided via environment variable
# attic_jwt_secret_base64 = "<from TF_VAR_attic_jwt_secret_base64>"
EOF

    log_warn "Please review and update $tfvars_file before proceeding"
    if ! $FORCE && ! $DRY_RUN; then
      read -rp "Continue with current configuration? (y/N) " confirm
      if [[ $confirm != "y" && $confirm != "Y" ]]; then
        log_error "Deployment cancelled - update tfvars and try again"
        exit 1
      fi
    fi
  fi
}

# Run OpenTofu plan
run_plan() {
  local iac_tool
  iac_tool=$(get_iac_tool)

  log_info "Running $iac_tool plan..."

  cd "$TOFU_DIR"

  local plan_args=("-var-file=terraform.tfvars" "-out=tfplan")

  # Add target args if specified
  if [[ -n $TARGETS ]]; then
    IFS=',' read -ra target_array <<<"$TARGETS"
    for target in "${target_array[@]}"; do
      plan_args+=("-target=$target")
    done
    log_info "Targeting: $TARGETS"
  fi

  if ! $iac_tool plan "${plan_args[@]}"; then
    log_error "Plan failed"
    exit 1
  fi

  log_success "Plan generated successfully"
}

# Run OpenTofu apply
run_apply() {
  local iac_tool
  iac_tool=$(get_iac_tool)

  if $DRY_RUN; then
    log_info "DRY RUN - would apply the following plan:"
    $iac_tool show tfplan
    return 0
  fi

  # Confirmation prompt
  if ! $FORCE; then
    log_warn "About to apply infrastructure changes to $ENVIRONMENT"
    read -rp "Proceed with deployment? (y/N) " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
      log_error "Deployment cancelled"
      exit 1
    fi
  fi

  log_info "Applying infrastructure changes..."

  cd "$TOFU_DIR"

  if ! $iac_tool apply -auto-approve tfplan; then
    log_error "Apply failed"
    exit 1
  fi

  log_success "Infrastructure changes applied"
}

# Wait for pods to be ready
wait_for_pods() {
  if $DRY_RUN; then
    log_info "DRY RUN - would wait for pods in namespace $NAMESPACE"
    return 0
  fi

  log_info "Waiting for pods to be ready..."

  # Wait for namespace to exist
  local max_attempts=30
  local attempt=0
  while ! kubectl get namespace "$NAMESPACE" &>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      log_error "Namespace $NAMESPACE not created after $max_attempts attempts"
      exit 1
    fi
    sleep 2
  done

  # Wait for API deployment
  log_info "Waiting for attic deployment..."
  if ! kubectl rollout status deployment/attic -n "$NAMESPACE" --timeout=300s 2>/dev/null; then
    log_warn "Attic API deployment not ready (may be new installation)"
  fi

  # Wait for GC deployment
  log_info "Waiting for attic-gc deployment..."
  if ! kubectl rollout status deployment/attic-gc -n "$NAMESPACE" --timeout=120s 2>/dev/null; then
    log_warn "Attic GC deployment not ready (may be new installation)"
  fi

  # Check PostgreSQL if using CNPG
  log_info "Checking PostgreSQL cluster..."
  if kubectl get cluster attic-pg -n "$NAMESPACE" &>/dev/null; then
    # Wait for CNPG cluster to be ready
    local pg_ready=false
    for i in {1..60}; do
      local phase
      phase=$(kubectl get cluster attic-pg -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
      if [[ $phase == "Cluster in healthy state" ]]; then
        pg_ready=true
        break
      fi
      log_debug "PostgreSQL status: $phase (attempt $i/60)"
      sleep 5
    done
    if $pg_ready; then
      log_success "PostgreSQL cluster is ready"
    else
      log_warn "PostgreSQL cluster may not be fully ready"
    fi
  fi

  log_success "Pods are ready"
}

# Extract deployment outputs
extract_outputs() {
  local iac_tool
  iac_tool=$(get_iac_tool)

  if $DRY_RUN; then
    log_info "DRY RUN - would extract outputs"
    return 0
  fi

  log_info "Extracting deployment outputs..."

  cd "$TOFU_DIR"

  echo ""
  echo "=========================================="
  echo "Deployment Outputs"
  echo "=========================================="

  $iac_tool output -json | jq -r '
        to_entries | .[] |
        select(.value.sensitive != true) |
        "\(.key): \(.value.value)"
    ' 2>/dev/null || log_warn "Could not extract outputs"

  echo ""
  echo "=========================================="
}

# Verify deployment health
verify_health() {
  if $DRY_RUN; then
    log_info "DRY RUN - would verify deployment health"
    return 0
  fi

  log_info "Verifying deployment health..."

  # Run health check script if available
  if [[ -x "$SCRIPT_DIR/health-check.sh" ]]; then
    if "$SCRIPT_DIR/health-check.sh" -n "$NAMESPACE"; then
      log_success "Health check passed"
    else
      log_warn "Health check reported issues - see above for details"
    fi
  else
    # Basic health checks
    log_info "Running basic health checks..."

    # Check pod status
    local ready_pods
    ready_pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | tr ' ' '\n' | grep -c "True" || echo "0")
    local total_pods
    total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")

    log_info "Pods ready: $ready_pods/$total_pods"

    # Check service endpoint
    if kubectl get endpoints attic -n "$NAMESPACE" &>/dev/null; then
      local endpoints
      endpoints=$(kubectl get endpoints attic -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
      if [[ -n $endpoints ]]; then
        log_success "Service has endpoints: $endpoints"
      else
        log_warn "Service has no endpoints"
      fi
    fi

    # Check ingress
    if kubectl get ingress attic -n "$NAMESPACE" &>/dev/null; then
      local ingress_ip
      ingress_ip=$(kubectl get ingress attic -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
      if [[ -n $ingress_ip ]]; then
        log_success "Ingress IP: $ingress_ip"
      else
        log_warn "Ingress has no IP assigned yet"
      fi
    fi
  fi
}

# Print post-deployment instructions
print_instructions() {
  if $DRY_RUN; then
    return 0
  fi

  echo ""
  echo "=========================================="
  echo "Deployment Complete"
  echo "=========================================="
  echo ""
  echo "Next Steps:"
  echo ""
  echo "1. Verify the deployment:"
  echo "   kubectl get pods -n $NAMESPACE"
  echo ""
  echo "2. Check the logs:"
  echo "   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=attic --tail=50"
  echo ""
  echo "3. Test the endpoint:"
  echo "   curl -s https://nix-cache.fuzzy-dev.tinyland.dev/nix-cache-info"
  echo ""
  echo "4. Create the main cache:"
  echo "   ./scripts/init-cache.sh"
  echo ""
  echo "5. Retrieve CI tokens:"
  echo "   kubectl get secret attic-ci-tokens -n $NAMESPACE -o jsonpath='{.data}' | jq"
  echo ""
  echo "For troubleshooting, see docs/RUNBOOK.md"
  echo ""
}

# Cleanup on failure
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_error "Deployment failed with exit code $exit_code"
    log_error "Check logs above for details"
    log_error ""
    log_error "To debug:"
    log_error "  kubectl get pods -n $NAMESPACE"
    log_error "  kubectl describe pods -n $NAMESPACE"
    log_error "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=attic"
  fi
}

# Main execution
main() {
  trap cleanup EXIT

  parse_args "$@"

  echo ""
  log_info "Attic Binary Cache Deployment"
  log_info "=============================="
  echo ""

  validate_environment
  check_prerequisites
  validate_env_vars
  verify_kubernetes

  init_tofu
  prepare_tfvars
  run_plan
  run_apply
  wait_for_pods
  extract_outputs
  verify_health
  print_instructions

  log_success "Deployment completed successfully!"
}

main "$@"
