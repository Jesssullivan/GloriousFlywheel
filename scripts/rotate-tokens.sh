#!/usr/bin/env bash
#
# rotate-tokens.sh - Automated token rotation for Attic
#
# This script checks for tokens approaching expiry and rotates them.
# Intended for scheduled execution via GitLab CI pipeline.
#
# Usage:
#   ./scripts/rotate-tokens.sh [options]
#
# Options:
#   --check-only    Only check expiry, don't rotate
#   --force         Force rotation regardless of expiry
#   --notify        Send notifications (requires SLACK_WEBHOOK_URL)
#
# Environment Variables:
#   NAMESPACE           Kubernetes namespace (default: nix-cache)
#   ROTATION_THRESHOLD  Days before expiry to trigger rotation (default: 14)
#   GITLAB_TOKEN        GitLab API token for updating CI/CD variables
#   GITHUB_TOKEN        GitHub token for updating Actions secrets
#   SLACK_WEBHOOK_URL   Slack webhook for notifications
#
# Exit Codes:
#   0 - Success (or no rotation needed)
#   1 - Error during rotation
#   2 - Check failed (tokens expiring but --check-only)

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-nix-cache}"
ROTATION_THRESHOLD="${ROTATION_THRESHOLD:-14}"
TOFU_DIR="${TOFU_DIR:-tofu/stacks/attic}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# State
CHECK_ONLY=false
FORCE_ROTATION=false
SEND_NOTIFICATIONS=false
TOKENS_ROTATED=()
TOKENS_EXPIRING=()
ERRORS=()

# Colors for output
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  NC=''
fi

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_header() { echo -e "\n${CYAN}=== $* ===${NC}" >&2; }

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Automated token rotation for Attic binary cache.

Options:
    --check-only    Only check for expiring tokens, don't rotate
    --force         Force rotation regardless of expiry status
    --notify        Send Slack notifications
    -h, --help      Show this help message

Environment Variables:
    NAMESPACE           Kubernetes namespace (default: nix-cache)
    ROTATION_THRESHOLD  Days before expiry to trigger rotation (default: 14)
    GITLAB_TOKEN        GitLab API token for updating CI/CD variables
    GITHUB_TOKEN        GitHub token for updating Actions secrets
    SLACK_WEBHOOK_URL   Slack webhook for notifications

Exit Codes:
    0 - Success (or no rotation needed)
    1 - Error during rotation
    2 - Tokens expiring but --check-only mode

Examples:
    # Check token status
    $(basename "$0") --check-only

    # Force rotation of all tokens
    $(basename "$0") --force

    # Rotate and notify
    $(basename "$0") --notify

EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --check-only)
    CHECK_ONLY=true
    shift
    ;;
  --force)
    FORCE_ROTATION=true
    shift
    ;;
  --notify)
    SEND_NOTIFICATIONS=true
    shift
    ;;
  -h | --help)
    usage
    ;;
  *)
    log_error "Unknown option: $1"
    exit 1
    ;;
  esac
done

# Check prerequisites
check_prerequisites() {
  local missing=()

  for cmd in kubectl jq date; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    exit 1
  fi

  # Check optional tools for CI updates
  if [[ -n ${GITLAB_TOKEN:-} ]] && ! command -v curl &>/dev/null; then
    log_warn "curl required for GitLab updates"
  fi

  if [[ -n ${GITHUB_TOKEN:-} ]] && ! command -v gh &>/dev/null; then
    log_warn "gh CLI required for GitHub updates"
  fi
}

# Verify Kubernetes connectivity
verify_kubernetes() {
  if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Cannot access namespace: $NAMESPACE"
    exit 1
  fi
}

# Get token expiry from secret annotations
get_token_expiry() {
  local secret_name="$1"

  local next_rotation
  next_rotation=$(kubectl get secret "$secret_name" -n "$NAMESPACE" \
    -o jsonpath='{.metadata.annotations.attic\.dev/next-rotation}' 2>/dev/null || true)

  if [[ -z $next_rotation ]]; then
    echo ""
    return
  fi

  echo "$next_rotation"
}

# Check if token needs rotation
needs_rotation() {
  local expiry_date="$1"
  local threshold_days="$2"

  if [[ -z $expiry_date ]]; then
    return 1 # No expiry date, don't rotate
  fi

  local expiry_epoch
  expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry_date" +%s 2>/dev/null)

  local now_epoch
  now_epoch=$(date +%s)

  local threshold_seconds=$((threshold_days * 24 * 3600))
  local time_remaining=$((expiry_epoch - now_epoch))

  if [[ $time_remaining -lt $threshold_seconds ]]; then
    return 0 # Needs rotation
  fi

  return 1 # Does not need rotation
}

# Format remaining time
format_remaining() {
  local expiry_date="$1"

  local expiry_epoch
  expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry_date" +%s 2>/dev/null)

  local now_epoch
  now_epoch=$(date +%s)

  local remaining=$((expiry_epoch - now_epoch))

  if [[ $remaining -lt 0 ]]; then
    echo "EXPIRED"
  elif [[ $remaining -lt 86400 ]]; then
    echo "$((remaining / 3600)) hours"
  else
    echo "$((remaining / 86400)) days"
  fi
}

# Check all token secrets
check_all_tokens() {
  log_header "Checking Token Expiry Status"

  local secrets=("attic-ci-tokens" "attic-readonly-tokens" "attic-service-tokens" "attic-root-token")

  for secret in "${secrets[@]}"; do
    if ! kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
      log_warn "Secret $secret not found"
      continue
    fi

    local expiry
    expiry=$(get_token_expiry "$secret")

    if [[ -z $expiry ]]; then
      log_info "$secret: No expiry annotation"
      continue
    fi

    local remaining
    remaining=$(format_remaining "$expiry")

    if needs_rotation "$expiry" "$ROTATION_THRESHOLD"; then
      log_warn "$secret: Expires in $remaining (threshold: ${ROTATION_THRESHOLD}d)"
      TOKENS_EXPIRING+=("$secret")
    else
      log_success "$secret: OK (expires in $remaining)"
    fi
  done

  echo "" >&2
  log_info "Tokens expiring within threshold: ${#TOKENS_EXPIRING[@]}"
}

# Get IaC tool
get_iac_tool() {
  if command -v tofu &>/dev/null; then
    echo "tofu"
  elif command -v terraform &>/dev/null; then
    echo "terraform"
  else
    log_error "Neither tofu nor terraform found"
    exit 1
  fi
}

# Perform token rotation via OpenTofu
rotate_tokens() {
  if [[ ${#TOKENS_EXPIRING[@]} -eq 0 ]] && ! $FORCE_ROTATION; then
    log_success "No tokens require rotation"
    return 0
  fi

  if $CHECK_ONLY; then
    log_warn "CHECK ONLY: Tokens require rotation but --check-only specified"
    return 2
  fi

  log_header "Rotating Tokens"

  local iac_tool
  iac_tool=$(get_iac_tool)

  local tofu_path="$REPO_ROOT/$TOFU_DIR"

  if [[ ! -d $tofu_path ]]; then
    log_error "OpenTofu directory not found: $tofu_path"
    exit 1
  fi

  cd "$tofu_path"

  # Force rotation by tainting time_rotating resources
  if $FORCE_ROTATION; then
    log_info "Force rotation requested - tainting time_rotating resources"

    # Taint rotation resources to force regeneration
    for resource in "time_rotating.ci_tokens" "time_rotating.service_tokens" "time_rotating.root_token"; do
      if $iac_tool state list 2>/dev/null | grep -q "module.attic_tokens.$resource"; then
        log_info "Tainting $resource"
        $iac_tool taint "module.attic_tokens.$resource" || true
      fi
    done
  fi

  # Plan and apply
  log_info "Planning token rotation..."

  if ! $iac_tool plan -var-file=terraform.tfvars -target=module.attic_tokens -out=rotation.tfplan; then
    log_error "Failed to plan token rotation"
    ERRORS+=("OpenTofu plan failed")
    return 1
  fi

  log_info "Applying token rotation..."

  if ! $iac_tool apply rotation.tfplan; then
    log_error "Failed to apply token rotation"
    ERRORS+=("OpenTofu apply failed")
    return 1
  fi

  rm -f rotation.tfplan

  log_success "Token rotation completed"

  # Record rotated tokens
  for token in "${TOKENS_EXPIRING[@]}"; do
    TOKENS_ROTATED+=("$token")
  done
}

# Update GitLab CI/CD variables
update_gitlab_variables() {
  if [[ -z ${GITLAB_TOKEN:-} ]]; then
    log_info "GITLAB_TOKEN not set, skipping GitLab updates"
    return 0
  fi

  log_header "Updating GitLab CI/CD Variables"

  # List of GitLab projects to update
  local projects=(
    "tinyland%2Fprojects%2Fgnucashr"
    "tinyland%2Fprojects%2Fattic-cache"
  )

  for project in "${projects[@]}"; do
    local token_name
    token_name=$(echo "$project" | sed 's/%2F/-/g')

    # Get token from Kubernetes
    local token_data
    token_data=$(kubectl get secret attic-ci-tokens -n "$NAMESPACE" \
      -o jsonpath="{.data.$token_name}" 2>/dev/null | base64 -d 2>/dev/null || true)

    if [[ -z $token_data ]]; then
      log_warn "Token not found for $token_name"
      continue
    fi

    local token_value
    token_value=$(echo "$token_data" | jq -r '.secret')

    log_info "Updating ATTIC_TOKEN for $project"

    local response
    response=$(curl -s -w "\n%{http_code}" \
      --request PUT \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --form "value=$token_value" \
      --form "protected=true" \
      --form "masked=true" \
      "https://gitlab.com/api/v4/projects/$project/variables/ATTIC_TOKEN" 2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [[ $http_code =~ ^2 ]]; then
      log_success "Updated GitLab variable for $project"
    else
      log_error "Failed to update GitLab variable for $project (HTTP $http_code)"
      ERRORS+=("GitLab update failed for $project")
    fi
  done
}

# Update GitHub Actions secrets
update_github_secrets() {
  if [[ -z ${GITHUB_TOKEN:-} ]]; then
    log_info "GITHUB_TOKEN not set, skipping GitHub updates"
    return 0
  fi

  if ! command -v gh &>/dev/null; then
    log_warn "gh CLI not available, skipping GitHub updates"
    return 0
  fi

  log_header "Updating GitHub Actions Secrets"

  # List of GitHub repos to update
  local repos=(
    "jesssullivan/gnucashr"
  )

  for repo in "${repos[@]}"; do
    local token_name
    token_name="github-$(echo "$repo" | tr '/' '-')"

    # Get token from Kubernetes
    local token_data
    token_data=$(kubectl get secret attic-ci-tokens -n "$NAMESPACE" \
      -o jsonpath="{.data.$token_name}" 2>/dev/null | base64 -d 2>/dev/null || true)

    if [[ -z $token_data ]]; then
      log_warn "Token not found for $token_name"
      continue
    fi

    local token_value
    token_value=$(echo "$token_data" | jq -r '.secret')

    log_info "Updating ATTIC_TOKEN for $repo"

    if gh secret set ATTIC_TOKEN --body "$token_value" --repo "$repo" 2>/dev/null; then
      log_success "Updated GitHub secret for $repo"
    else
      log_error "Failed to update GitHub secret for $repo"
      ERRORS+=("GitHub update failed for $repo")
    fi
  done
}

# Send Slack notification
send_notification() {
  if ! $SEND_NOTIFICATIONS; then
    return 0
  fi

  if [[ -z ${SLACK_WEBHOOK_URL:-} ]]; then
    log_warn "SLACK_WEBHOOK_URL not set, skipping notifications"
    return 0
  fi

  log_header "Sending Notifications"

  local status="success"
  local color="#36a64f"
  local title="Attic Token Rotation Complete"

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    status="warning"
    color="#ff9800"
    title="Attic Token Rotation Completed with Errors"
  fi

  local rotated_list="None"
  if [[ ${#TOKENS_ROTATED[@]} -gt 0 ]]; then
    rotated_list=$(printf '%s\n' "${TOKENS_ROTATED[@]}" | paste -sd ',' -)
  fi

  local error_list="None"
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    error_list=$(printf '%s\n' "${ERRORS[@]}" | paste -sd ',' -)
  fi

  local payload
  payload=$(
    cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "$title",
            "fields": [
                {
                    "title": "Tokens Rotated",
                    "value": "$rotated_list",
                    "short": true
                },
                {
                    "title": "Errors",
                    "value": "$error_list",
                    "short": true
                },
                {
                    "title": "Environment",
                    "value": "$NAMESPACE",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
                    "short": true
                }
            ]
        }
    ]
}
EOF
  )

  if curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL" &>/dev/null; then
    log_success "Notification sent"
  else
    log_error "Failed to send notification"
  fi
}

# Print summary
print_summary() {
  log_header "Rotation Summary"

  echo "Tokens checked:   ${#TOKENS_EXPIRING[@]}" >&2
  echo "Tokens rotated:   ${#TOKENS_ROTATED[@]}" >&2
  echo "Errors:           ${#ERRORS[@]}" >&2

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "" >&2
    log_error "Errors encountered:"
    for error in "${ERRORS[@]}"; do
      echo "  - $error" >&2
    done
  fi
}

# Main execution
main() {
  log_header "Attic Token Rotation"
  log_info "Namespace: $NAMESPACE"
  log_info "Rotation threshold: ${ROTATION_THRESHOLD} days"
  log_info "Mode: $(if $CHECK_ONLY; then echo "CHECK ONLY"; elif $FORCE_ROTATION; then echo "FORCE"; else echo "AUTO"; fi)"

  check_prerequisites
  verify_kubernetes

  # Check token status
  check_all_tokens

  # Perform rotation if needed
  local rotation_result=0
  rotate_tokens || rotation_result=$?

  # Update CI/CD systems if tokens were rotated
  if [[ ${#TOKENS_ROTATED[@]} -gt 0 ]]; then
    update_gitlab_variables
    update_github_secrets
  fi

  # Send notifications
  send_notification

  # Print summary
  print_summary

  # Exit with appropriate code
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    exit 1
  elif [[ $rotation_result -eq 2 ]]; then
    exit 2 # Check-only mode found expiring tokens
  fi

  exit 0
}

main "$@"
