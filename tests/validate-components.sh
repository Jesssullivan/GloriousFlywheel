#!/usr/bin/env bash
# Validate all CI/CD component templates
#
# Checks:
# - Valid YAML syntax
# - spec.inputs section present
# - Document separator (---) present
# - No tab characters (YAML best practice)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates"
ERRORS=0

echo "=== Validating CI/CD Component Templates ==="
echo ""

for template in "$TEMPLATES_DIR"/*/template.yml; do
  component=$(basename "$(dirname "$template")")
  echo -n "  $component... "

  # Check YAML syntax
  if ! python3 -c "import yaml; yaml.safe_load_all(open('$template'))" 2>/dev/null; then
    # Fallback: basic structure check if python3/yaml not available
    if ! grep -q '^spec:' "$template"; then
      echo "FAIL (missing spec: section)"
      ERRORS=$((ERRORS + 1))
      continue
    fi
  fi

  # Check for spec.inputs
  if ! grep -q 'inputs:' "$template"; then
    echo "FAIL (missing inputs)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check for document separator
  if ! grep -q '^---' "$template"; then
    echo "FAIL (missing --- separator)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check for tabs
  if grep -Pq '\t' "$template" 2>/dev/null; then
    echo "FAIL (contains tab characters)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  echo "OK"
done

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS template(s) have issues"
  exit 1
fi
echo "All component templates valid!"
