#!/usr/bin/env bash
# Runner Pool Health Check
# Checks pod status, HPA, metrics, and cluster resources for all 5 runner types.
# Exit 1 if any runner is down.
set -euo pipefail

NAMESPACE="${NAMESPACE:-gitlab-runners}"
RUNNERS=("runner-docker" "runner-dind" "runner-rocky8" "runner-rocky9" "runner-nix")
ERRORS=0

echo "=== Runner Pool Health Check ==="
echo "Namespace: ${NAMESPACE}"
echo ""

# Check each runner
for runner in "${RUNNERS[@]}"; do
  echo "--- ${runner} ---"

  # Pod status
  PODS=$(kubectl get pods -n "${NAMESPACE}" -l "release=${runner}" --no-headers 2>/dev/null | wc -l)
  READY=$(kubectl get pods -n "${NAMESPACE}" -l "release=${runner}" --no-headers 2>/dev/null | grep -c "Running" || true)
  echo "  Pods: ${READY}/${PODS} running"

  # HPA status
  HPA=$(kubectl get hpa "${runner}-hpa" -n "${NAMESPACE}" -o jsonpath='{.status.currentReplicas}/{.status.desiredReplicas}' 2>/dev/null || echo "N/A")
  echo "  HPA: ${HPA}"

  # Metrics endpoint
  METRICS=$(kubectl get svc "${runner}-metrics" -n "${NAMESPACE}" 2>/dev/null && echo "OK" || echo "N/A")
  echo "  Metrics: ${METRICS}"

  if [ "${PODS}" -eq 0 ]; then
    echo "  STATUS: DOWN"
    ERRORS=$((ERRORS + 1))
  elif [ "${READY}" -lt "${PODS}" ]; then
    echo "  STATUS: DEGRADED"
  else
    echo "  STATUS: HEALTHY"
  fi
  echo ""
done

# Overall
echo "=== Summary ==="

# PDB check
PDB_COUNT=$(kubectl get pdb -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
echo "PDBs: ${PDB_COUNT}"

# ServiceMonitor check
SM_COUNT=$(kubectl get servicemonitor -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
echo "ServiceMonitors: ${SM_COUNT}"

# NetworkPolicy check
NP_COUNT=$(kubectl get networkpolicy -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
echo "NetworkPolicies: ${NP_COUNT}"

# ResourceQuota check
kubectl get resourcequota runner-quota -n "${NAMESPACE}" \
  -o jsonpath='Quota CPU: {.status.used.requests\.cpu}/{.status.hard.requests\.cpu}' 2>/dev/null && echo "" || echo "Quota: N/A"
kubectl get resourcequota runner-quota -n "${NAMESPACE}" \
  -o jsonpath='Quota Memory: {.status.used.requests\.memory}/{.status.hard.requests\.memory}' 2>/dev/null && echo "" || echo ""

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "DEGRADED: ${ERRORS} runner(s) down"
  exit 1
fi
echo "All runners healthy!"
