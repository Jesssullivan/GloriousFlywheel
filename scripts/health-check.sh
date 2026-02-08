#!/usr/bin/env bash
#
# health-check.sh - Unified health check for Attic binary cache
#
# Supports both CI/CD pipelines and local development with optional
# Kubernetes operator awareness and comprehensive status reporting.
#
# Usage:
#   ./scripts/health-check.sh [options]
#
# Options:
#   -u, --url URL          Health check URL (required)
#   -n, --namespace NS     Kubernetes namespace (enables K8s checks)
#   -m, --max-attempts N   Maximum retry attempts (default: 15)
#   -d, --initial-delay S  Initial delay in seconds (default: 30)
#   -M, --max-delay S      Maximum delay between attempts (default: 60)
#   -k, --k8s-check        Enable Kubernetes operator status checks
#   -j, --json             Output results as JSON
#   -q, --quiet            Only output failures
#   -v, --verbose          Enable verbose output
#   -h, --help             Show this help
#
# Environment Variables:
#   HEALTH_URL             Alternative to -u flag
#   HEALTH_NAMESPACE       Alternative to -n flag
#   HEALTH_MAX_ATTEMPTS    Alternative to -m flag
#   HEALTH_INITIAL_DELAY   Alternative to -d flag
#   HEALTH_MAX_DELAY       Alternative to -M flag
#
# Exit Codes:
#   0 - Health check passed
#   1 - Health check failed after all attempts
#   2 - Configuration error
#
# Examples:
#   # Simple CI health check
#   ./scripts/health-check.sh -u https://attic-cache.dev.example.com/
#
#   # With Kubernetes operator awareness
#   ./scripts/health-check.sh -u https://attic-cache.dev.example.com/ -n attic-cache -k
#
#   # Local development with all checks
#   ./scripts/health-check.sh -u https://attic-cache.prod.example.com/ -n attic-cache -v

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Defaults (can be overridden by environment or flags)
URL="${HEALTH_URL:-}"
NAMESPACE="${HEALTH_NAMESPACE:-}"
MAX_ATTEMPTS="${HEALTH_MAX_ATTEMPTS:-15}"
INITIAL_DELAY="${HEALTH_INITIAL_DELAY:-30}"
MAX_DELAY="${HEALTH_MAX_DELAY:-60}"
K8S_CHECK=false
JSON_OUTPUT=false
QUIET=false
VERBOSE=false

# Track results for comprehensive mode
declare -A CHECK_RESULTS 2>/dev/null || true
FAILED_CHECKS=0
PASSED_CHECKS=0

# =============================================================================
# Colors (disabled in non-TTY)
# =============================================================================

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

# =============================================================================
# Logging
# =============================================================================

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

# =============================================================================
# Usage
# =============================================================================

usage() {
  head -40 "$0" | tail -35
  exit 0
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -u | --url)
      URL="$2"
      shift 2
      ;;
    -n | --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -m | --max-attempts)
      MAX_ATTEMPTS="$2"
      shift 2
      ;;
    -d | --initial-delay)
      INITIAL_DELAY="$2"
      shift 2
      ;;
    -M | --max-delay)
      MAX_DELAY="$2"
      shift 2
      ;;
    -k | --k8s-check)
      K8S_CHECK=true
      shift
      ;;
    -j | --json)
      JSON_OUTPUT=true
      QUIET=true
      shift
      ;;
    -q | --quiet)
      QUIET=true
      shift
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      log_fail "Unknown option: $1"
      exit 2
      ;;
    esac
  done
}

# =============================================================================
# Result Tracking (for comprehensive mode)
# =============================================================================

record_check() {
  local name="$1"
  local status="$2"
  local message="${3:-}"

  if declare -p CHECK_RESULTS &>/dev/null; then
    CHECK_RESULTS["$name"]="$status"
  fi

  if [[ $status == "pass" ]]; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_pass "$name: $message"
  else
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    log_fail "$name: $message"
  fi
}

# =============================================================================
# Kubernetes Checks
# =============================================================================

check_operators() {
  if ! command -v kubectl &>/dev/null || [[ -z $NAMESPACE ]]; then
    return 0
  fi

  log_info "Checking operator status..."

  # Check CNPG operator
  if kubectl get namespace cnpg-system &>/dev/null; then
    local cnpg_ready
    cnpg_ready=$(kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg \
      --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
    if [[ $cnpg_ready -gt 0 ]]; then
      log_debug "CNPG operator: Ready ($cnpg_ready pods)"
    else
      log_warn "CNPG operator: Not ready"
    fi
  fi

  # Check CNPG cluster status
  if kubectl get cluster -n "$NAMESPACE" &>/dev/null; then
    local cluster_phase
    cluster_phase=$(kubectl get cluster -n "$NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    log_debug "PostgreSQL cluster: $cluster_phase"
  fi

  # Check MinIO operator
  if kubectl get namespace minio-operator &>/dev/null; then
    local minio_ready
    minio_ready=$(kubectl get pods -n minio-operator -l app.kubernetes.io/name=operator \
      --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
    if [[ $minio_ready -gt 0 ]]; then
      log_debug "MinIO operator: Ready ($minio_ready pods)"
    else
      log_warn "MinIO operator: Not ready"
    fi
  fi

  # Check MinIO tenant
  if kubectl get tenant -n "$NAMESPACE" &>/dev/null; then
    local tenant_phase
    tenant_phase=$(kubectl get tenant -n "$NAMESPACE" -o jsonpath='{.items[0].status.currentState}' 2>/dev/null || echo "Unknown")
    log_debug "MinIO tenant: $tenant_phase"
  fi
}

check_pods() {
  if ! command -v kubectl &>/dev/null || [[ -z $NAMESPACE ]]; then
    return 0
  fi

  log_info "Pod status in ${NAMESPACE}:"
  kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -10 || echo "  (no pods or access denied)"
}

check_pod_details() {
  if ! command -v kubectl &>/dev/null || [[ -z $NAMESPACE ]]; then
    return 0
  fi

  # Get pod information
  local pods_json
  pods_json=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null) || return 0

  # Check Attic API pods
  local attic_pods attic_ready
  attic_pods=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"]=="attic")] | length')
  attic_ready=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"]=="attic") | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

  if [[ $attic_ready -gt 0 ]]; then
    record_check "attic_api_pods" "pass" "$attic_ready/$attic_pods pods ready"
  elif [[ $attic_pods -gt 0 ]]; then
    record_check "attic_api_pods" "fail" "0/$attic_pods pods ready"
  fi

  # Check PostgreSQL pods (CNPG)
  local pg_pods pg_ready
  pg_pods=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["cnpg.io/cluster"])] | length')
  if [[ $pg_pods -gt 0 ]]; then
    pg_ready=$(echo "$pods_json" | jq '[.items[] | select(.metadata.labels["cnpg.io/cluster"]) | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
    if [[ $pg_ready -gt 0 ]]; then
      record_check "postgresql_pods" "pass" "$pg_ready/$pg_pods pods ready"
    else
      record_check "postgresql_pods" "fail" "0/$pg_pods pods ready"
    fi
  fi

  # Check for crash loops
  local crash_loops
  crash_loops=$(echo "$pods_json" | jq '[.items[] | select(.status.containerStatuses[]? | select(.restartCount > 5))] | length')
  if [[ $crash_loops -gt 0 ]]; then
    record_check "crash_loops" "fail" "$crash_loops pods with excessive restarts"
  fi
}

# =============================================================================
# HTTP Health Check
# =============================================================================

check_http_health() {
  local delay=$INITIAL_DELAY
  local attempt=0

  while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
    attempt=$((attempt + 1))

    if ! $QUIET; then
      echo "[$(date '+%H:%M:%S')] Attempt ${attempt}/${MAX_ATTEMPTS}..."
    fi

    local http_code
    http_code=$(curl -sSo /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$URL" 2>/dev/null || echo "000")

    if [[ $http_code == "200" ]]; then
      if ! $QUIET; then
        echo ""
        echo -e "${GREEN}=== Health check PASSED (HTTP $http_code) ===${NC}"
        curl -sS "$URL" 2>/dev/null || true
        echo ""
      fi
      record_check "http_health" "pass" "HTTP $http_code"
      return 0
    fi

    if ! $QUIET; then
      echo "  HTTP $http_code - waiting ${delay}s..."
    fi

    # Show pod status periodically on failures
    if $K8S_CHECK && [[ $((attempt % 3)) -eq 0 ]]; then
      check_pods
    fi

    if [[ $attempt -lt $MAX_ATTEMPTS ]]; then
      sleep "$delay"
      # Exponential backoff
      delay=$((delay + 15))
      if [[ $delay -gt $MAX_DELAY ]]; then
        delay=$MAX_DELAY
      fi
    fi
  done

  echo ""
  log_fail "Health check FAILED after ${MAX_ATTEMPTS} attempts"
  record_check "http_health" "fail" "All attempts exhausted"
  return 1
}

# =============================================================================
# JSON Output
# =============================================================================

output_json() {
  local results=()

  if declare -p CHECK_RESULTS &>/dev/null; then
    for check in "${!CHECK_RESULTS[@]}"; do
      results+=("{\"check\": \"$check\", \"status\": \"${CHECK_RESULTS[$check]}\"}")
    done
  fi

  local json_array
  if [[ ${#results[@]} -gt 0 ]]; then
    json_array=$(printf '%s\n' "${results[@]}" | jq -s '.')
  else
    json_array="[]"
  fi

  jq -n \
    --argjson checks "$json_array" \
    --arg passed "$PASSED_CHECKS" \
    --arg failed "$FAILED_CHECKS" \
    --arg url "$URL" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      timestamp: $timestamp,
      url: $url,
      summary: {
        passed: ($passed | tonumber),
        failed: ($failed | tonumber),
        total: (($passed | tonumber) + ($failed | tonumber))
      },
      checks: $checks
    }'
}

# =============================================================================
# Main
# =============================================================================

main() {
  parse_args "$@"

  # Validate required arguments
  if [[ -z $URL ]]; then
    log_fail "URL is required (-u/--url or HEALTH_URL env var)"
    exit 2
  fi

  # Header
  if ! $QUIET; then
    echo ""
    echo "=== Attic Cache Health Check ==="
    echo "URL: ${URL}"
    echo "Max attempts: ${MAX_ATTEMPTS}, Initial delay: ${INITIAL_DELAY}s, Max delay: ${MAX_DELAY}s"
    if [[ -n $NAMESPACE ]]; then
      echo "Namespace: ${NAMESPACE}"
    fi
    echo ""
  fi

  # Initial operator status (if K8s check enabled)
  if $K8S_CHECK; then
    check_operators
    echo ""
  fi

  # Main HTTP health check with retries
  local http_result=0
  check_http_health || http_result=$?

  # Additional K8s checks (verbose mode)
  if $VERBOSE && [[ -n $NAMESPACE ]]; then
    check_pod_details
  fi

  # Final status dump on failure
  if [[ $http_result -ne 0 ]] && $K8S_CHECK; then
    echo ""
    check_operators
    check_pods
    echo ""
    echo "Manual verification:"
    echo "  curl -v ${URL}"
  fi

  # JSON output
  if $JSON_OUTPUT; then
    output_json
  fi

  exit $http_result
}

main "$@"
