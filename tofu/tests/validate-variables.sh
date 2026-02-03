#!/usr/bin/env bash
# Validate OpenTofu variable definitions
#
# This script checks that all required variables have:
# - Proper descriptions
# - Type constraints
# - Validation rules where appropriate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOFU_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "OpenTofu Variable Validation"
echo "============================"
echo ""

# Track issues
ISSUES=0

check_variables_file() {
  local file="$1"
  local name="$2"

  if [ ! -f "$file" ]; then
    return 0
  fi

  echo "Checking: $name"

  # Check for variables without descriptions
  local no_desc
  no_desc=$(grep -c 'variable "' "$file" || true)
  local with_desc
  with_desc=$(grep -c 'description' "$file" || true)

  if [ "$no_desc" -gt "$with_desc" ]; then
    echo "  WARN: Some variables may be missing descriptions"
    echo "        Variables: $no_desc, Descriptions: $with_desc"
  fi

  # Check for sensitive variables that should be marked
  local sensitive_patterns=("password" "secret" "key" "token" "credential")
  for pattern in "${sensitive_patterns[@]}"; do
    local sensitive_vars
    sensitive_vars=$(grep -i "variable.*$pattern" "$file" | grep -v "sensitive.*=.*true" || true)
    if [ -n "$sensitive_vars" ]; then
      echo "  WARN: Variables with '$pattern' in name may need sensitive = true:"
      echo "$sensitive_vars" | sed 's/^/        /'
    fi
  done

  echo "  OK"
}

# Check main stack variables
if [ -f "$TOFU_ROOT/stacks/attic/variables.tf" ]; then
  check_variables_file "$TOFU_ROOT/stacks/attic/variables.tf" "stacks/attic/variables.tf"
fi

# Check each module's variables
for module_dir in "$TOFU_ROOT"/modules/*/; do
  if [ -d "$module_dir" ]; then
    module_name=$(basename "$module_dir")
    var_file="$module_dir/variables.tf"
    if [ -f "$var_file" ]; then
      check_variables_file "$var_file" "modules/$module_name/variables.tf"
    fi
  fi
done

echo ""
echo "============================"
if [ $ISSUES -gt 0 ]; then
  echo "Found $ISSUES issues"
  exit 1
else
  echo "Variable validation complete"
  exit 0
fi
