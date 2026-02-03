#!/usr/bin/env bash
# Configuration validation tests
#
# This script validates various configuration files in the repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Configuration Validation"
echo "========================"

FAILED=0

# Validate flake.nix syntax
echo ""
echo "Checking: flake.nix"
if [ -f "$REPO_ROOT/flake.nix" ]; then
  if command -v nix &>/dev/null; then
    if nix flake check --no-build "$REPO_ROOT" 2>/dev/null; then
      echo "  PASS: Nix flake is valid"
    else
      echo "  FAIL: Nix flake check failed"
      FAILED=1
    fi
  else
    echo "  SKIP: Nix not available"
  fi
else
  echo "  FAIL: flake.nix not found"
  FAILED=1
fi

# Validate flake.lock exists
echo ""
echo "Checking: flake.lock"
if [ -f "$REPO_ROOT/flake.lock" ]; then
  echo "  PASS: flake.lock exists"
else
  echo "  FAIL: flake.lock not found (run 'nix flake update')"
  FAILED=1
fi

# Validate .gitlab-ci.yml syntax
echo ""
echo "Checking: .gitlab-ci.yml"
if [ -f "$REPO_ROOT/.gitlab-ci.yml" ]; then
  # Basic YAML syntax check
  if command -v python3 &>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$REPO_ROOT/.gitlab-ci.yml'))" 2>/dev/null; then
      echo "  PASS: Valid YAML syntax"
    else
      echo "  FAIL: Invalid YAML syntax"
      FAILED=1
    fi
  else
    echo "  SKIP: Python not available for YAML validation"
  fi
else
  echo "  FAIL: .gitlab-ci.yml not found"
  FAILED=1
fi

# Check for sensitive files that should not exist
echo ""
echo "Checking: No sensitive files committed"

SENSITIVE_PATTERNS=(
  "terraform.tfvars.bak"
  "*.pem"
  "*.key"
  ".env"
  ".env.*"
)

SENSITIVE_FOUND=0
for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  found=$(find "$REPO_ROOT" -name "$pattern" -not -path "*/.git/*" -not -path "*/result/*" 2>/dev/null | head -5)
  if [ -n "$found" ]; then
    echo "  WARN: Found sensitive file pattern '$pattern':"
    echo "$found" | sed 's/^/    /'
    SENSITIVE_FOUND=1
  fi
done

if [ $SENSITIVE_FOUND -eq 0 ]; then
  echo "  PASS: No sensitive files found"
fi

# Check .gitignore includes common patterns
echo ""
echo "Checking: .gitignore coverage"
if [ -f "$REPO_ROOT/.gitignore" ]; then
  REQUIRED_PATTERNS=("*.tfstate" "*.tfvars" ".terraform/" ".env")
  MISSING=0
  for pattern in "${REQUIRED_PATTERNS[@]}"; do
    if ! grep -q "$pattern" "$REPO_ROOT/.gitignore"; then
      echo "  WARN: Missing pattern '$pattern' in .gitignore"
      MISSING=1
    fi
  done
  if [ $MISSING -eq 0 ]; then
    echo "  PASS: Essential patterns present"
  fi
else
  echo "  FAIL: .gitignore not found"
  FAILED=1
fi

echo ""
echo "========================"
if [ $FAILED -eq 0 ]; then
  echo "All configuration checks passed"
else
  echo "Some configuration checks failed"
  exit 1
fi
