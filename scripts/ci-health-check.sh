#!/usr/bin/env bash
#
# ci-health-check.sh - CI/CD Health check with operator awareness
#
# Designed for GitLab CI jobs that need to wait for:
#   - CNPG operator and PostgreSQL cluster
#   - MinIO operator and tenant
#   - Attic deployment and ingress
#
# Usage:
#   ./scripts/ci-health-check.sh [options]
#
# Options:
#   -u, --url URL          Health check URL (required)
#   -n, --namespace NS     Kubernetes namespace (optional, enables operator checks)
#   -m, --max-attempts N   Maximum attempts (default: 15)
#   -d, --initial-delay S  Initial delay in seconds (default: 30)
#   -M, --max-delay S      Maximum delay between attempts (default: 60)
#   -k, --k8s-check        Enable Kubernetes operator status checks
#   -h, --help             Show this help
#
# Exit Codes:
#   0 - Health check passed
#   1 - Health check failed after all attempts
#   2 - Configuration error

set -euo pipefail

# Default configuration
URL=""
NAMESPACE=""
MAX_ATTEMPTS=15
INITIAL_DELAY=30
MAX_DELAY=60
K8S_CHECK=false

# Parse arguments
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
  -h | --help)
    head -35 "$0" | tail -30
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    exit 2
    ;;
  esac
done

if [[ -z $URL ]]; then
  echo "ERROR: URL is required (-u/--url)"
  exit 2
fi

echo "=== CI Health Check ==="
echo "URL: ${URL}"
echo "Max attempts: ${MAX_ATTEMPTS}"
echo "Initial delay: ${INITIAL_DELAY}s, Max delay: ${MAX_DELAY}s"
if [[ -n $NAMESPACE ]]; then
  echo "Namespace: ${NAMESPACE}"
fi
echo ""

# Check operator status (if kubectl available and namespace set)
check_operators() {
  if ! command -v kubectl &>/dev/null || [[ -z $NAMESPACE ]]; then
    return 0
  fi

  echo "--- Checking operator status ---"

  # Check CNPG operator
  if kubectl get namespace cnpg-system &>/dev/null; then
    CNPG_READY=$(kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg \
      --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
    if [[ $CNPG_READY -gt 0 ]]; then
      echo "  CNPG operator: Ready ($CNPG_READY pods)"
    else
      echo "  CNPG operator: Not ready"
    fi
  fi

  # Check CNPG cluster status
  if kubectl get cluster -n "$NAMESPACE" &>/dev/null; then
    CLUSTER_PHASE=$(kubectl get cluster -n "$NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    echo "  PostgreSQL cluster: $CLUSTER_PHASE"
  fi

  # Check MinIO operator
  if kubectl get namespace minio-operator &>/dev/null; then
    MINIO_READY=$(kubectl get pods -n minio-operator -l app.kubernetes.io/name=operator \
      --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
    if [[ $MINIO_READY -gt 0 ]]; then
      echo "  MinIO operator: Ready ($MINIO_READY pods)"
    else
      echo "  MinIO operator: Not ready"
    fi
  fi

  # Check MinIO tenant
  if kubectl get tenant -n "$NAMESPACE" &>/dev/null; then
    TENANT_PHASE=$(kubectl get tenant -n "$NAMESPACE" -o jsonpath='{.items[0].status.currentState}' 2>/dev/null || echo "Unknown")
    echo "  MinIO tenant: $TENANT_PHASE"
  fi

  echo ""
}

# Check pod status
check_pods() {
  if ! command -v kubectl &>/dev/null || [[ -z $NAMESPACE ]]; then
    return 0
  fi

  echo "--- Pod status in ${NAMESPACE} ---"
  kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -10 || echo "  (no pods or access denied)"
  echo ""
}

# Main health check loop
DELAY=$INITIAL_DELAY
ATTEMPT=0

# Initial operator status check
if $K8S_CHECK; then
  check_operators
fi

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  ATTEMPT=$((ATTEMPT + 1))

  echo "[$(date '+%H:%M:%S')] Attempt ${ATTEMPT}/${MAX_ATTEMPTS}..."

  # Perform HTTP check
  HTTP_CODE=$(curl -sSo /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$URL" 2>/dev/null || echo "000")

  if [[ $HTTP_CODE == "200" ]]; then
    echo ""
    echo "=== Health check PASSED (HTTP $HTTP_CODE) ==="
    curl -sS "$URL"
    echo ""
    exit 0
  fi

  echo "  HTTP $HTTP_CODE"

  # Show pod status on failures (helpful for debugging)
  if $K8S_CHECK && [[ $((ATTEMPT % 3)) -eq 0 ]]; then
    check_pods
  fi

  if [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; then
    echo "  Waiting ${DELAY}s before retry..."
    sleep "$DELAY"

    # Exponential backoff
    DELAY=$((DELAY + 15))
    if [[ $DELAY -gt $MAX_DELAY ]]; then
      DELAY=$MAX_DELAY
    fi
  fi
done

echo ""
echo "=== Health check FAILED after ${MAX_ATTEMPTS} attempts ==="

# Final status dump
if $K8S_CHECK; then
  echo ""
  check_operators
  check_pods
fi

echo ""
echo "Manual verification command:"
echo "  curl -v ${URL}"

exit 1
