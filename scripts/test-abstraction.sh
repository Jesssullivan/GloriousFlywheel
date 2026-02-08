#!/usr/bin/env bash
# scripts/test-abstraction.sh - Test abstraction implementation

set -euo pipefail

echo "=== Abstraction Testing Checklist ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
  echo -e "${GREEN}✅ $1${NC}"
}

fail() {
  echo -e "${RED}❌ $1${NC}"
  exit 1
}

warn() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

# 1. Config validation
echo "1. Validating organization config..."
if ./scripts/validate-org-config.sh config/organization.yaml >/dev/null 2>&1; then
  pass "Organization config is valid"
else
  fail "Organization config validation failed"
fi
echo ""

# 2. No hardcoded organization references in core modules
echo "2. Checking for hardcoded organization references in modules..."

# Check tofu/modules for hardcoded organization-specific references
if grep -r "bates-ils" tofu/modules/ 2>/dev/null | grep -v ".terraform" | grep -v "# "; then
  fail "Found hardcoded organization references in tofu/modules/"
fi

# Check for hardcoded example domains
if grep -r "\.bates\.edu" tofu/modules/ 2>/dev/null | grep -v ".terraform"; then
  fail "Found hardcoded organization domains in tofu/modules/"
fi

# Check for hardcoded GitLab project ID in core files (allow in tfvars)
if grep -r "78189586" tofu/modules/ tofu/stacks/*/main.tf tofu/stacks/*/variables.tf 2>/dev/null | grep -v ".terraform"; then
  fail "Found hardcoded GitLab project ID in core files"
fi

pass "No hardcoded organization references in core modules"
echo ""

# 3. Test config loading
echo "3. Testing config loading..."
if [ -f scripts/lib/config.sh ]; then
  # shellcheck disable=SC1091
  source scripts/lib/config.sh
  if load_org_config config/organization.yaml >/dev/null 2>&1; then
    if [ -n "${GITLAB_PROJECT_ID:-}" ] && [ -n "${ORG_NAME:-}" ]; then
      pass "Config loading works (ORG_NAME=$ORG_NAME, PROJECT_ID=$GITLAB_PROJECT_ID)"
    else
      fail "Config loaded but variables not exported"
    fi
  else
    fail "Config loading failed"
  fi
else
  fail "scripts/lib/config.sh not found"
fi
echo ""

# 4. Test Justfile integration
echo "4. Testing Justfile integration..."
if command -v just &>/dev/null; then
  # Check that variables can be evaluated
  if gitlab_project=$(just --evaluate gitlab_project 2>/dev/null); then
    if [ -n "$gitlab_project" ]; then
      pass "Justfile loads org config correctly (project=$gitlab_project)"
    else
      warn "Justfile project ID is empty"
    fi
  else
    fail "Justfile variable evaluation failed"
  fi
else
  warn "just not installed, skipping Justfile test"
fi
echo ""

# 5. Test example config
echo "5. Testing example organization config..."
if [ -f config/organization.example.yaml ]; then
  if ./scripts/validate-org-config.sh config/organization.example.yaml >/dev/null 2>&1; then
    pass "Example config is valid"
  else
    fail "Example config validation failed"
  fi
else
  fail "config/organization.example.yaml not found"
fi
echo ""

# 6. Test environment switching
echo "6. Testing environment context resolution..."
if command -v yq &>/dev/null; then
  first_cluster=$(yq '.clusters[0].name' config/organization.yaml)
  first_context=$(yq '.clusters[0].context' config/organization.yaml)

  if [ -n "$first_cluster" ] && [ -n "$first_context" ]; then
    pass "Environment contexts are configured (${first_cluster}=${first_context})"
  else
    fail "Environment context not found in organization config"
  fi
else
  warn "yq not installed, skipping environment test"
fi
echo ""

# 7. Check .gitignore
echo "7. Checking .gitignore for organization.yaml..."
if grep -q "config/organization.yaml" .gitignore; then
  pass "config/organization.yaml is in .gitignore"
else
  fail "config/organization.yaml is NOT in .gitignore"
fi
echo ""

# Summary
echo ""
echo "=== All Abstraction Tests Passed ==="
echo ""
echo "Next steps:"
echo "  1. Test with your organization config"
echo "  2. Run 'ENV=dev just tofu-plan attic' to verify no changes"
echo "  3. Run 'ENV=prod just tofu-plan attic' to verify no changes"
echo "  4. Commit changes and push for CI validation"
