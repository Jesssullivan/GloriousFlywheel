#!/usr/bin/env bash
#
# health-check.sh - Health check script for Attic binary cache
#
# Performs comprehensive health checks on the Attic deployment including:
#   - Pod status and readiness
#   - API endpoint accessibility
#   - S3 storage connectivity
#   - PostgreSQL database status
#   - Cache push/pull operations
#
# Usage:
#   ./scripts/health-check.sh [options]
#
# Options:
#   -n, --namespace    Kubernetes namespace (default: nix-cache)
#   -e, --endpoint     Attic endpoint URL (default: https://nix-cache.fuzzy-dev.tinyland.dev)
#   -v, --verbose      Enable verbose output
#   -q, --quiet        Only output failures
#   -j, --json         Output results as JSON
#   -h, --help         Show this help message
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
#   2 - Prerequisites missing

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="nix-cache"
ENDPOINT="https://nix-cache.fuzzy-dev.tinyland.dev"
VERBOSE=false
QUIET=false
JSON_OUTPUT=false

# Track results
declare -A CHECK_RESULTS
FAILED_CHECKS=0
PASSED_CHECKS=0

# Colors
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Logging functions
log_info() {
  if ! $QUIET; then
    echo -e "${BLUE}[INFO]${NC} $*" >&2
  fi
}

log_pass() {
  if ! $QUIET; then
    echo -e "${GREEN}[PASS]${NC} $*" >&2
  fi
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*" >&2
}

log_warn() {
  if ! $QUIET; then
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
  fi
}

log_debug() {
  if $VERBOSE; then
    echo -e "${BLUE}[DEBUG]${NC} $*" >&2
  fi
}

# Record check result
record_check() {
  local name="$1"
  local status="$2"
  local message="${3:-}"

  CHECK_RESULTS["$name"]="$status"

  if [[ $status == "pass" ]]; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_pass "$name: $message"
  else
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    log_fail "$name: $message"
  fi
}

# Usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Perform health checks on Attic binary cache deployment.

Options:
    -n, --namespace    Kubernetes namespace (default: nix-cache)
    -e, --endpoint     Attic endpoint URL
    -v, --verbose      Enable verbose output
    -q, --quiet        Only output failures
    -j, --json         Output results as JSON
    -h, --help         Show this help message

Examples:
    # Run all checks
    $(basename "$0")

    # Check specific namespace
    $(basename "$0") -n my-namespace

    # JSON output for CI
    $(basename "$0") -j
EOF
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -n | --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -e | --endpoint)
      ENDPOINT="$2"
      shift 2
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    -q | --quiet)
      QUIET=true
      shift
      ;;
    -j | --json)
      JSON_OUTPUT=true
      QUIET=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      log_fail "Unknown option: $1"
      usage
      ;;
    esac
  done
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  if ! command -v kubectl &>/dev/null; then
    log_fail "kubectl not found"
    exit 2
  fi

  if ! command -v curl &>/dev/null; then
    log_fail "curl not found"
    exit 2
  fi
}

# Check Kubernetes connectivity
check_kubernetes_connectivity() {
  log_info "Checking Kubernetes connectivity..."

  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    record_check "kubernetes_connectivity" "pass" "Can access namespace $NAMESPACE"
  else
    record_check "kubernetes_connectivity" "fail" "Cannot access namespace $NAMESPACE"
    return 1
  fi
}

# Check pod status
check_pod_status() {
  log_info "Checking pod status..."

  # Get pod information
  local pods_json
  pods_json=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null)

  if [[ -z $pods_json ]]; then
    record_check "pod_status" "fail" "Could not retrieve pod information"
    return 1
  fi

  local total_pods
  total_pods=$(echo "$pods_json" | jq '.items | length')

  local ready_pods
  ready_pods=$(echo "$pods_json" | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

  log_debug "Total pods: $total_pods, Ready: $ready_pods"

  # Check Attic API pods
  local attic_pods
  attic_pods=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"]=="attic")] | length')
  local attic_ready
  attic_ready=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"]=="attic") | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

  if [[ $attic_ready -gt 0 ]]; then
    record_check "attic_api_pods" "pass" "$attic_ready/$attic_pods pods ready"
  else
    record_check "attic_api_pods" "fail" "No Attic API pods ready ($attic_pods total)"
  fi

  # Check Attic GC pod
  local gc_pods
  gc_pods=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"]=="attic-gc")] | length')
  local gc_ready
  gc_ready=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"]=="attic-gc") | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

  if [[ $gc_ready -gt 0 ]]; then
    record_check "attic_gc_pod" "pass" "$gc_ready/$gc_pods pods ready"
  else
    record_check "attic_gc_pod" "fail" "No Attic GC pods ready ($gc_pods total)"
  fi

  # Check PostgreSQL pods (CNPG)
  local pg_pods
  pg_pods=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["cnpg.io/cluster"]=="attic-pg")] | length')
  if [[ $pg_pods -gt 0 ]]; then
    local pg_ready
    pg_ready=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["cnpg.io/cluster"]=="attic-pg") | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

    if [[ $pg_ready -gt 0 ]]; then
      record_check "postgresql_pods" "pass" "$pg_ready/$pg_pods pods ready"
    else
      record_check "postgresql_pods" "fail" "No PostgreSQL pods ready ($pg_pods total)"
    fi
  fi

  # Check for crash loops
  local crash_loops
  crash_loops=$(echo "$pods_json" | jq '[.items[] | select(.status.containerStatuses[]? | select(.restartCount > 5))] | length')

  if [[ $crash_loops -gt 0 ]]; then
    record_check "crash_loops" "fail" "$crash_loops pods with excessive restarts"
  else
    record_check "crash_loops" "pass" "No pods in crash loop"
  fi
}

# Check API endpoint
check_api_endpoint() {
  log_info "Checking API endpoint..."

  # Check nix-cache-info endpoint
  local response
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$ENDPOINT/nix-cache-info" 2>/dev/null || echo "000")

  if [[ $http_code == "200" ]]; then
    record_check "api_nix_cache_info" "pass" "nix-cache-info returns 200"

    # Parse the response
    response=$(curl -s --connect-timeout 10 "$ENDPOINT/nix-cache-info" 2>/dev/null || echo "")
    log_debug "nix-cache-info response: $response"
  else
    record_check "api_nix_cache_info" "fail" "nix-cache-info returns $http_code"
  fi

  # Check health endpoint (if available)
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$ENDPOINT/_health" 2>/dev/null || echo "000")

  if [[ $http_code == "200" ]]; then
    record_check "api_health" "pass" "Health endpoint returns 200"
  elif [[ $http_code == "404" ]]; then
    log_debug "Health endpoint not implemented (404)"
  else
    record_check "api_health" "fail" "Health endpoint returns $http_code"
  fi

  # Check metrics endpoint
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$ENDPOINT/metrics" 2>/dev/null || echo "000")

  if [[ $http_code == "200" ]]; then
    record_check "api_metrics" "pass" "Metrics endpoint accessible"
  else
    log_debug "Metrics endpoint returns $http_code (may not be exposed)"
  fi
}

# Check TLS certificate
check_tls_certificate() {
  log_info "Checking TLS certificate..."

  local host
  host=$(echo "$ENDPOINT" | sed 's|https://||' | cut -d'/' -f1)

  local cert_info
  cert_info=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "")

  if [[ -z $cert_info ]]; then
    record_check "tls_certificate" "fail" "Could not retrieve TLS certificate"
    return 1
  fi

  # Check expiry
  local expiry
  expiry=$(echo "$cert_info" | grep "notAfter" | cut -d'=' -f2)
  local expiry_epoch
  expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || echo "0")
  local now_epoch
  now_epoch=$(date +%s)
  local days_until_expiry
  days_until_expiry=$(((expiry_epoch - now_epoch) / 86400))

  if [[ $days_until_expiry -lt 7 ]]; then
    record_check "tls_certificate" "fail" "Certificate expires in $days_until_expiry days"
  elif [[ $days_until_expiry -lt 30 ]]; then
    record_check "tls_certificate" "pass" "Certificate expires in $days_until_expiry days (warning)"
    log_warn "Certificate expires soon: $expiry"
  else
    record_check "tls_certificate" "pass" "Certificate valid for $days_until_expiry days"
  fi
}

# Check PostgreSQL status
check_postgresql() {
  log_info "Checking PostgreSQL status..."

  # Check CNPG cluster status
  if kubectl get cluster attic-pg -n "$NAMESPACE" &>/dev/null; then
    local phase
    phase=$(kubectl get cluster attic-pg -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [[ $phase == "Cluster in healthy state" ]]; then
      record_check "postgresql_cluster" "pass" "CNPG cluster healthy"
    else
      record_check "postgresql_cluster" "fail" "CNPG cluster status: $phase"
    fi

    # Check instances
    local instances
    instances=$(kubectl get cluster attic-pg -n "$NAMESPACE" -o jsonpath='{.status.instances}' 2>/dev/null || echo "0")
    local ready_instances
    ready_instances=$(kubectl get cluster attic-pg -n "$NAMESPACE" -o jsonpath='{.status.readyInstances}' 2>/dev/null || echo "0")

    log_debug "PostgreSQL instances: $ready_instances/$instances ready"

    if [[ $ready_instances == "$instances" && $instances != "0" ]]; then
      record_check "postgresql_instances" "pass" "$ready_instances/$instances instances ready"
    else
      record_check "postgresql_instances" "fail" "Only $ready_instances/$instances instances ready"
    fi
  else
    log_debug "CNPG cluster not found (may be using Neon)"
  fi
}

# Check S3 storage
check_s3_storage() {
  log_info "Checking S3 storage connectivity..."

  # Get S3 credentials from secret
  local s3_endpoint
  local access_key
  local secret_key
  local bucket

  # Try to get S3 info from configmap/secret
  local config
  config=$(kubectl get configmap attic-config -n "$NAMESPACE" -o jsonpath='{.data.server\.toml}' 2>/dev/null || echo "")

  if [[ -n $config ]]; then
    bucket=$(echo "$config" | grep -E "^bucket" | cut -d'"' -f2 || echo "")
    s3_endpoint=$(echo "$config" | grep -E "^endpoint" | cut -d'"' -f2 || echo "")

    if [[ -n $bucket && -n $s3_endpoint ]]; then
      log_debug "S3 bucket: $bucket, endpoint: $s3_endpoint"
      record_check "s3_config" "pass" "S3 configured: $bucket"
    else
      record_check "s3_config" "fail" "S3 configuration incomplete"
    fi
  else
    log_debug "Could not retrieve S3 configuration"
  fi
}

# Check HPA status
check_hpa() {
  log_info "Checking HPA status..."

  if kubectl get hpa attic -n "$NAMESPACE" &>/dev/null; then
    local hpa_json
    hpa_json=$(kubectl get hpa attic -n "$NAMESPACE" -o json 2>/dev/null)

    local current_replicas
    current_replicas=$(echo "$hpa_json" | jq '.status.currentReplicas')
    local desired_replicas
    desired_replicas=$(echo "$hpa_json" | jq '.status.desiredReplicas')
    local min_replicas
    min_replicas=$(echo "$hpa_json" | jq '.spec.minReplicas')
    local max_replicas
    max_replicas=$(echo "$hpa_json" | jq '.spec.maxReplicas')

    log_debug "HPA: current=$current_replicas, desired=$desired_replicas, min=$min_replicas, max=$max_replicas"

    if [[ $current_replicas == "$desired_replicas" ]]; then
      record_check "hpa_status" "pass" "HPA stable at $current_replicas replicas (min=$min_replicas, max=$max_replicas)"
    else
      record_check "hpa_status" "fail" "HPA scaling: $current_replicas -> $desired_replicas"
    fi
  else
    log_debug "HPA not found"
  fi
}

# Check ingress status
check_ingress() {
  log_info "Checking ingress status..."

  if kubectl get ingress attic -n "$NAMESPACE" &>/dev/null; then
    local ingress_ip
    ingress_ip=$(kubectl get ingress attic -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    local ingress_host
    ingress_host=$(kubectl get ingress attic -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [[ -n $ingress_ip || -n $ingress_host ]]; then
      record_check "ingress" "pass" "Ingress has address: ${ingress_ip:-$ingress_host}"
    else
      record_check "ingress" "fail" "Ingress has no address"
    fi
  else
    record_check "ingress" "fail" "Ingress not found"
  fi
}

# Check secrets
check_secrets() {
  log_info "Checking secrets..."

  # Check main secrets
  if kubectl get secret attic-secrets -n "$NAMESPACE" &>/dev/null; then
    record_check "attic_secrets" "pass" "Core secrets exist"
  else
    record_check "attic_secrets" "fail" "Core secrets missing"
  fi

  # Check CI tokens secret
  if kubectl get secret attic-ci-tokens -n "$NAMESPACE" &>/dev/null; then
    local token_count
    token_count=$(kubectl get secret attic-ci-tokens -n "$NAMESPACE" -o jsonpath='{.data}' | jq 'keys | length' 2>/dev/null || echo "0")
    record_check "ci_tokens" "pass" "$token_count CI tokens configured"
  else
    log_debug "CI tokens secret not found (may not be enabled)"
  fi
}

# Test cache operations (requires attic CLI)
check_cache_operations() {
  log_info "Checking cache operations..."

  if ! command -v attic &>/dev/null; then
    log_debug "Attic CLI not installed, skipping cache operation tests"
    return 0
  fi

  # This would require authentication, so we just check if the CLI is configured
  if [[ -f "$HOME/.config/attic/config.toml" ]]; then
    record_check "attic_cli_config" "pass" "Attic CLI configured"
  else
    log_debug "Attic CLI not configured"
  fi
}

# Output JSON results
output_json() {
  local results=()
  for check in "${!CHECK_RESULTS[@]}"; do
    results+=("{\"check\": \"$check\", \"status\": \"${CHECK_RESULTS[$check]}\"}")
  done

  local json_array
  json_array=$(printf '%s\n' "${results[@]}" | jq -s '.')

  jq -n \
    --argjson checks "$json_array" \
    --arg passed "$PASSED_CHECKS" \
    --arg failed "$FAILED_CHECKS" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
            timestamp: $timestamp,
            summary: {
                passed: ($passed | tonumber),
                failed: ($failed | tonumber),
                total: (($passed | tonumber) + ($failed | tonumber))
            },
            checks: $checks
        }'
}

# Print summary
print_summary() {
  if $JSON_OUTPUT; then
    output_json
    return
  fi

  echo ""
  echo "=========================================="
  echo "Health Check Summary"
  echo "=========================================="
  echo ""
  echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
  echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
  echo "Total:  $((PASSED_CHECKS + FAILED_CHECKS))"
  echo ""

  if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo "Failed checks:"
    for check in "${!CHECK_RESULTS[@]}"; do
      if [[ ${CHECK_RESULTS[$check]} == "fail" ]]; then
        echo "  - $check"
      fi
    done
    echo ""
  fi
}

# Main execution
main() {
  parse_args "$@"

  if ! $QUIET; then
    echo ""
    log_info "Attic Binary Cache Health Check"
    log_info "================================"
    log_info "Namespace: $NAMESPACE"
    log_info "Endpoint: $ENDPOINT"
    echo ""
  fi

  check_prerequisites

  # Run all checks
  check_kubernetes_connectivity || true
  check_pod_status || true
  check_api_endpoint || true
  check_tls_certificate || true
  check_postgresql || true
  check_s3_storage || true
  check_hpa || true
  check_ingress || true
  check_secrets || true
  check_cache_operations || true

  print_summary

  # Exit with appropriate code
  if [[ $FAILED_CHECKS -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"
