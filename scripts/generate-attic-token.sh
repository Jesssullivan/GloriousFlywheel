#!/usr/bin/env bash
#
# generate-attic-token.sh - Generate JWT tokens for Attic binary cache
#
# Creates HS256-signed JWTs for authenticating to the Attic API.
# The signing key is the same one configured in the Attic server's
# [jwt.signing] token-hs256-secret-base64 setting.
#
# Usage:
#   ./scripts/generate-attic-token.sh <base64-secret> [options]
#
# Options:
#   -s, --sub         Token subject (default: ci-push)
#   -d, --days        Token validity in days (default: 365)
#   -c, --cache       Cache name to authorize (default: main)
#   --admin           Grant full admin permissions (r/w/cc on all caches)
#   -h, --help        Show this help message
#
# The base64-secret can be obtained from:
#   tofu -chdir=tofu/stacks/attic output -raw jwt_signing_secret_base64
#
# Or from the K8s secret:
#   kubectl get secret attic-jwt-signing -n <ns> -o jsonpath='{.data.hs256-secret-base64}' | base64 -d
#
# Prerequisites:
#   - openssl (for HMAC-SHA256 signing)
#
# Examples:
#   # Generate a CI push token (1 year, main cache, read+write)
#   ./scripts/generate-attic-token.sh "$(tofu output -raw jwt_signing_secret_base64)"
#
#   # Generate an admin token (1 hour, all caches)
#   ./scripts/generate-attic-token.sh "$SECRET" --admin -d 0.04
#
#   # Generate a read-only token for a specific cache
#   ./scripts/generate-attic-token.sh "$SECRET" -c my-cache -s "readonly" -d 30

set -euo pipefail

# Defaults
SUB="ci-push"
DAYS=365
CACHE="main"
ADMIN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") <base64-secret> [options]

Generate JWT tokens for Attic binary cache authentication.

Arguments:
    base64-secret    Base64-encoded HS256 signing key

Options:
    -s, --sub        Token subject (default: $SUB)
    -d, --days       Token validity in days (default: $DAYS)
    -c, --cache      Cache name to authorize (default: $CACHE)
    --admin          Grant full admin permissions (r/w/cc on all caches)
    -h, --help       Show this help message

Get the signing key:
    tofu -chdir=tofu/stacks/attic output -raw jwt_signing_secret_base64
EOF
  exit 0
}

# Parse args
SECRET_B64=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -s | --sub) SUB="$2"; shift 2 ;;
    -d | --days) DAYS="$2"; shift 2 ;;
    -c | --cache) CACHE="$2"; shift 2 ;;
    --admin) ADMIN=true; shift ;;
    -h | --help) usage ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z $SECRET_B64 ]]; then
        SECRET_B64="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

if [[ -z $SECRET_B64 ]]; then
  echo "Error: base64-secret argument is required" >&2
  echo "" >&2
  usage
fi

if ! command -v openssl &>/dev/null; then
  echo "Error: openssl is required but not found" >&2
  exit 1
fi

# Decode the signing key
SECRET=$(echo -n "$SECRET_B64" | base64 -d)

# base64url encode (no padding, URL-safe alphabet)
b64url() { base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

# Build JWT header
HEADER=$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)

# Compute expiry
EXP=$(python3 -c "import time; print(int(time.time() + $DAYS * 86400))" 2>/dev/null \
  || echo $(( $(date +%s) + ${DAYS%.*} * 86400 )))

# Build claims
if $ADMIN; then
  CLAIMS=$(printf '{"sub":"%s","exp":%s,"https://jwt.attic.rs/v1":{"caches":{"*":{"r":1,"w":1,"cc":1}}}}' "$SUB" "$EXP")
else
  CLAIMS=$(printf '{"sub":"%s","exp":%s,"https://jwt.attic.rs/v1":{"caches":{"%s":{"r":1,"w":1}}}}' "$SUB" "$EXP" "$CACHE")
fi

PAYLOAD=$(echo -n "$CLAIMS" | b64url)

# Sign
SIG=$(printf '%s.%s' "$HEADER" "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)

# Output token
echo "$HEADER.$PAYLOAD.$SIG"
