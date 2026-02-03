#!/usr/bin/env bash
# Validate all OpenTofu modules
#
# This script validates each module independently without
# initializing backends or making real provider calls.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOFU_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "OpenTofu Module Validation"
echo "=========================="
echo "Tofu root: $TOFU_ROOT"
echo ""

# Check if tofu is available
if ! command -v tofu &>/dev/null; then
  echo "ERROR: OpenTofu (tofu) is required but not found"
  echo "Install with: nix-env -iA nixpkgs.opentofu"
  exit 1
fi

tofu version
echo ""

# Track results
PASSED=0
FAILED=0
SKIPPED=0

# Validate each module
for module_dir in "$TOFU_ROOT"/modules/*/; do
  if [ -d "$module_dir" ]; then
    module_name=$(basename "$module_dir")
    echo "Module: $module_name"

    cd "$module_dir"

    # Check for main.tf or *.tf files
    if ! ls *.tf >/dev/null 2>&1; then
      echo "  SKIP: No .tf files found"
      ((SKIPPED++))
      cd - >/dev/null
      continue
    fi

    # Initialize without backend
    if ! tofu init -backend=false -input=false -no-color >/dev/null 2>&1; then
      echo "  FAIL: Initialization failed"
      ((FAILED++))
      cd - >/dev/null
      continue
    fi

    # Validate the module
    if tofu validate -no-color; then
      echo "  PASS"
      ((PASSED++))
    else
      echo "  FAIL"
      ((FAILED++))
    fi

    # Cleanup
    rm -rf .terraform .terraform.lock.hcl 2>/dev/null || true

    cd - >/dev/null
  fi
done

echo ""
echo "=========================="
echo "Summary:"
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo ""

if [ $FAILED -gt 0 ]; then
  echo "RESULT: Some modules failed validation"
  exit 1
else
  echo "RESULT: All modules validated successfully"
  exit 0
fi
