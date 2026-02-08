#!/usr/bin/env bash
# Cache Warm Script
#
# Pre-populates the Attic Nix binary cache with common derivations.
# Run on a schedule or after flake updates.
#
# Prerequisites:
#   - nix with flakes enabled
#   - attic-client installed
#   - ATTIC_SERVER and ATTIC_TOKEN set
#
# Usage:
#   ./scripts/cache-warm.sh                    # Warm all common derivations
#   ./scripts/cache-warm.sh --server URL       # Custom Attic server
#   ./scripts/cache-warm.sh --cache CACHE      # Custom cache name

set -euo pipefail

ATTIC_SERVER="${ATTIC_SERVER:-}"
ATTIC_CACHE="${ATTIC_CACHE:-main}"
ATTIC_TOKEN="${ATTIC_TOKEN:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --server)
    ATTIC_SERVER="$2"
    shift 2
    ;;
  --cache)
    ATTIC_CACHE="$2"
    shift 2
    ;;
  *)
    echo "Unknown argument: $1"
    exit 1
    ;;
  esac
done

echo "=== Attic Cache Warm ==="
echo "Server: ${ATTIC_SERVER}"
echo "Cache:  ${ATTIC_CACHE}"
echo ""

# Login to Attic
if [ -n "${ATTIC_TOKEN}" ]; then
  attic login default "${ATTIC_SERVER}" "${ATTIC_TOKEN}"
else
  echo "WARNING: ATTIC_TOKEN not set, push will fail"
fi

# Common derivations to warm the cache
DERIVATIONS=(
  "nixpkgs#hello"
  "nixpkgs#coreutils"
  "nixpkgs#bash"
  "nixpkgs#git"
  "nixpkgs#curl"
  "nixpkgs#jq"
  "nixpkgs#opentofu"
  "nixpkgs#kubectl"
  "nixpkgs#attic-client"
  "nixpkgs#nodejs_20"
  "nixpkgs#python3"
)

ERRORS=0
for drv in "${DERIVATIONS[@]}"; do
  echo -n "  Building ${drv}... "
  if nix build "${drv}" --no-link 2>/dev/null; then
    STORE_PATH=$(nix path-info "${drv}" 2>/dev/null || echo "")
    if [ -n "${STORE_PATH}" ] && [ -n "${ATTIC_TOKEN}" ]; then
      attic push "${ATTIC_CACHE}" "${STORE_PATH}" 2>/dev/null && echo "pushed" || echo "push failed"
    else
      echo "built (no push)"
    fi
  else
    echo "FAILED"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "Completed with ${ERRORS} error(s)"
  exit 1
fi
echo "Cache warm complete!"
