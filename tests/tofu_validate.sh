#!/usr/bin/env bash
# Validate OpenTofu modules
#
# This script validates all OpenTofu module configurations
# without actually initializing backends or providers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "OpenTofu Module Validation"
echo "=========================="

# Check if tofu is available
if ! command -v tofu &>/dev/null; then
  echo "SKIP: OpenTofu (tofu) not available"
  exit 0
fi

# Track validation status
FAILED=0

# Validate each module
for module_dir in "$REPO_ROOT"/tofu/modules/*/; do
  if [ -d "$module_dir" ]; then
    module_name=$(basename "$module_dir")
    echo ""
    echo "Validating module: $module_name"
    echo "---"

    cd "$module_dir"

    # Initialize without backend (for validation only)
    if ! tofu init -backend=false -input=false >/dev/null 2>&1; then
      echo "  FAIL: init failed"
      FAILED=1
      continue
    fi

    # Validate the module
    if tofu validate; then
      echo "  PASS"
    else
      echo "  FAIL: validation failed"
      FAILED=1
    fi

    cd - >/dev/null
  fi
done

# Validate the main stack
echo ""
echo "Validating stack: attic"
echo "---"

cd "$REPO_ROOT/tofu/stacks/attic"

if ! tofu init -backend=false -input=false >/dev/null 2>&1; then
  echo "  FAIL: init failed"
  FAILED=1
else
  if tofu validate; then
    echo "  PASS"
  else
    echo "  FAIL: validation failed"
    FAILED=1
  fi
fi

echo ""
echo "=========================="
if [ $FAILED -eq 0 ]; then
  echo "All modules validated successfully"
else
  echo "Some modules failed validation"
  exit 1
fi
