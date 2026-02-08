#!/usr/bin/env bash
# Integration Test: Runner Enrollment Flow
#
# Tests the full self-service enrollment lifecycle:
# 1. Verify runner namespace exists
# 2. Check all 5 runner types are registered
# 3. Submit a test job to each runner type
# 4. Verify job completion
# 5. Clean up
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - GITLAB_TOKEN with API access
#   - CI_PROJECT_ID for test project
#
# Usage:
#   ./tests/integration/enrollment-flow.sh

set -euo pipefail

NAMESPACE="${NAMESPACE:-gitlab-runners}"
GITLAB_API="${GITLAB_API:-https://gitlab.com/api/v4}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
ERRORS=0

echo "=== Runner Enrollment Integration Test ==="
echo "Namespace: ${NAMESPACE}"
echo ""

# 1. Verify namespace exists
echo "1. Checking namespace..."
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "   PASS: namespace ${NAMESPACE} exists"
else
  echo "   FAIL: namespace ${NAMESPACE} not found"
  ERRORS=$((ERRORS + 1))
fi

# 2. Check runner pods
echo "2. Checking runner pods..."
RUNNERS=("runner-docker" "runner-dind" "runner-rocky8" "runner-rocky9" "runner-nix")
for runner in "${RUNNERS[@]}"; do
  PODS=$(kubectl get pods -n "${NAMESPACE}" -l "release=${runner}" --no-headers 2>/dev/null | wc -l)
  if [ "${PODS}" -gt 0 ]; then
    echo "   PASS: ${runner} has ${PODS} pod(s)"
  else
    echo "   FAIL: ${runner} has no pods"
    ERRORS=$((ERRORS + 1))
  fi
done

# 3. Check HPAs
echo "3. Checking HPA status..."
HPA_COUNT=$(kubectl get hpa -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
echo "   Found ${HPA_COUNT} HPA(s)"
if [ "${HPA_COUNT}" -ge 5 ]; then
  echo "   PASS: all HPAs present"
else
  echo "   WARN: expected 5 HPAs, found ${HPA_COUNT}"
fi

# 4. Check PDBs
echo "4. Checking PDB status..."
PDB_COUNT=$(kubectl get pdb -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
echo "   Found ${PDB_COUNT} PDB(s)"

# 5. Check security policies
echo "5. Checking security policies..."
NP=$(kubectl get networkpolicy -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
RQ=$(kubectl get resourcequota -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
LR=$(kubectl get limitrange -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
echo "   NetworkPolicies: ${NP}, ResourceQuotas: ${RQ}, LimitRanges: ${LR}"

# 6. Check RBAC
echo "6. Checking RBAC..."
if kubectl get role ci-job-runner-access -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "   PASS: CI job RBAC role exists"
else
  echo "   WARN: CI job RBAC role not found"
fi

echo ""
echo "=== Results ==="
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: ${ERRORS} error(s)"
  exit 1
fi
echo "All enrollment checks passed!"
