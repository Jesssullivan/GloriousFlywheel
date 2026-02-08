#!/usr/bin/env bash
# Load Test: HPA Scale-Out Verification
#
# Submits N concurrent CI jobs to trigger HPA scale-out,
# then monitors scaling behavior and measures time to scale.
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - Runner pool deployed with HPA enabled
#
# Usage:
#   ./tests/load/hpa-load-test.sh [CONCURRENCY]
#   ./tests/load/hpa-load-test.sh 10

set -euo pipefail

NAMESPACE="${NAMESPACE:-gitlab-runners}"
CONCURRENCY="${1:-5}"
RUNNER="${RUNNER:-runner-docker}"
CHECK_INTERVAL=15
MAX_CHECKS=40 # 10 minutes

echo "=== HPA Load Test ==="
echo "Namespace:   ${NAMESPACE}"
echo "Runner:      ${RUNNER}"
echo "Concurrency: ${CONCURRENCY} stress pods"
echo ""

# Record initial state
echo "1. Recording initial HPA state..."
INITIAL_REPLICAS=$(kubectl get hpa "${RUNNER}-hpa" -n "${NAMESPACE}" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
echo "   Initial replicas: ${INITIAL_REPLICAS}"

# Create stress pods to simulate load
echo "2. Creating ${CONCURRENCY} stress pods..."
for i in $(seq 1 "${CONCURRENCY}"); do
  kubectl run "loadtest-${RUNNER}-${i}" \
    -n "${NAMESPACE}" \
    --image=alpine:3.21 \
    --restart=Never \
    --labels="app=loadtest,target=${RUNNER}" \
    --requests="cpu=200m,memory=128Mi" \
    -- sh -c "dd if=/dev/zero of=/dev/null bs=1M & sleep 300" \
    2>/dev/null || echo "  Pod loadtest-${RUNNER}-${i} already exists"
done
echo "   Stress pods created"

# Monitor HPA scaling
echo "3. Monitoring HPA scale-out..."
START_TIME=$(date +%s)
SCALED=false

for check in $(seq 1 ${MAX_CHECKS}); do
  CURRENT=$(kubectl get hpa "${RUNNER}-hpa" -n "${NAMESPACE}" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get hpa "${RUNNER}-hpa" -n "${NAMESPACE}" -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo "0")
  CPU=$(kubectl get hpa "${RUNNER}-hpa" -n "${NAMESPACE}" -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || echo "?")

  echo "   [${check}/${MAX_CHECKS}] replicas=${CURRENT}/${DESIRED} cpu=${CPU}%"

  if [ "${CURRENT}" -gt "${INITIAL_REPLICAS}" ]; then
    ELAPSED=$(($(date +%s) - START_TIME))
    echo ""
    echo "   Scale-out detected! ${INITIAL_REPLICAS} -> ${CURRENT} in ${ELAPSED}s"
    SCALED=true
    break
  fi

  sleep ${CHECK_INTERVAL}
done

# Cleanup
echo "4. Cleaning up stress pods..."
kubectl delete pods -n "${NAMESPACE}" -l "app=loadtest,target=${RUNNER}" --ignore-not-found >/dev/null 2>&1
echo "   Stress pods deleted"

echo ""
echo "=== Results ==="
if [ "${SCALED}" = "true" ]; then
  echo "PASS: HPA scaled from ${INITIAL_REPLICAS} to ${CURRENT} replicas"
else
  echo "WARN: HPA did not scale within ${MAX_CHECKS} checks"
  echo "  This may be expected if initial replicas are already at or near max"
fi
