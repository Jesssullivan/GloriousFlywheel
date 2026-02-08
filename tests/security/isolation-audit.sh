#!/usr/bin/env bash
# Security Audit: Runner Isolation Verification
#
# Verifies security controls are in place:
# - NetworkPolicy (default-deny ingress)
# - ResourceQuota limits
# - LimitRange defaults
# - namespace_per_job isolation
# - RBAC scoping
#
# Prerequisites:
#   - kubectl configured with cluster access
#
# Usage:
#   ./tests/security/isolation-audit.sh

set -euo pipefail

NAMESPACE="${NAMESPACE:-gitlab-runners}"
ERRORS=0
WARNINGS=0

echo "=== Runner Security Isolation Audit ==="
echo "Namespace: ${NAMESPACE}"
echo ""

# 1. NetworkPolicy
echo "1. NetworkPolicy Check"
if kubectl get networkpolicy default-deny-ingress -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "   PASS: default-deny-ingress policy exists"
else
  echo "   FAIL: default-deny-ingress policy missing"
  ERRORS=$((ERRORS + 1))
fi

# 2. ResourceQuota
echo "2. ResourceQuota Check"
QUOTA=$(kubectl get resourcequota runner-quota -n "${NAMESPACE}" -o json 2>/dev/null || echo "")
if [ -n "${QUOTA}" ]; then
  echo "   PASS: runner-quota exists"
  CPU=$(echo "${QUOTA}" | jq -r '.spec.hard["requests.cpu"] // "not set"')
  MEM=$(echo "${QUOTA}" | jq -r '.spec.hard["requests.memory"] // "not set"')
  PODS=$(echo "${QUOTA}" | jq -r '.spec.hard.pods // "not set"')
  echo "   CPU: ${CPU}, Memory: ${MEM}, Pods: ${PODS}"
else
  echo "   FAIL: runner-quota missing"
  ERRORS=$((ERRORS + 1))
fi

# 3. LimitRange
echo "3. LimitRange Check"
if kubectl get limitrange runner-limits -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "   PASS: runner-limits exists"
else
  echo "   FAIL: runner-limits missing"
  ERRORS=$((ERRORS + 1))
fi

# 4. RBAC Scope Check
echo "4. RBAC Scope Check"
ROLE=$(kubectl get role ci-job-runner-access -n "${NAMESPACE}" -o json 2>/dev/null || echo "")
if [ -n "${ROLE}" ]; then
  VERBS=$(echo "${ROLE}" | jq -r '.rules[0].verbs | join(",")')
  echo "   PASS: CI job role exists with verbs: ${VERBS}"
  # Verify no write verbs
  if echo "${VERBS}" | grep -qE "create|update|delete|patch"; then
    echo "   WARN: CI job role has write access"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "   PASS: CI job role is read-only"
  fi
else
  echo "   WARN: CI job role not found (may not be deployed yet)"
  WARNINGS=$((WARNINGS + 1))
fi

# 5. Namespace-per-job orphan check
echo "5. Orphaned Namespace Check"
ORPHANS=$(kubectl get namespaces -o name 2>/dev/null | grep "ci-job-" | wc -l)
echo "   Active ci-job-* namespaces: ${ORPHANS}"
if [ "${ORPHANS}" -gt 10 ]; then
  echo "   WARN: many ci-job namespaces, cleanup may be needed"
  WARNINGS=$((WARNINGS + 1))
else
  echo "   PASS: namespace count within normal range"
fi

# 6. ServiceMonitor check
echo "6. ServiceMonitor Check"
SM_COUNT=$(kubectl get servicemonitor -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
echo "   ServiceMonitors: ${SM_COUNT}"

echo ""
echo "=== Audit Results ==="
echo "Errors:   ${ERRORS}"
echo "Warnings: ${WARNINGS}"
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: ${ERRORS} security issue(s) found"
  exit 1
fi
echo "Security audit passed!"
