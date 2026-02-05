# Attic Cache - Unified Task Runner
# ==================================
#
# Consolidated task automation for the attic-cache infrastructure project.
# Provides a unified entry point for all common operations.
#
# Prerequisites:
#   - just (https://github.com/casey/just)
#   - direnv (loads Nix devShell automatically)
#   - Nix with flakes enabled
#
# Quick Start:
#   just                    # List all commands
#   just check              # Run all validations
#   just tofu-plan attic    # Plan Attic stack deployment
#
# Environment Selection:
#   ENV=rigel just tofu-plan attic   # Target rigel cluster
#   ENV=beehive just tofu-plan attic # Target beehive cluster (default)

# Default recipe - list available commands
default:
    @just --list --unsorted

# =============================================================================
# Configuration
# =============================================================================

# Environment: beehive (dev) or rigel (staging/prod)
env := env_var_or_default("ENV", "beehive")

# GitLab project for state storage
gitlab_project := "78189586"
gitlab_api := "https://gitlab.com/api/v4"

# Kubernetes context based on environment
kube_context := if env == "beehive" {
    "bates-ils/projects/kubernetes/gitlab-agents:beehive"
} else {
    "bates-ils/projects/kubernetes/gitlab-agents:rigel"
}

# Ingress domain based on environment
ingress_domain := if env == "beehive" { "beehive.bates.edu" } else { "rigel.bates.edu" }

# =============================================================================
# Development Workflows
# =============================================================================

# Quick validation cycle (format + lint + validate)
check: fmt-check nix-check tofu-fmt-check
    @echo "All checks passed!"

# Full validation including tofu (requires initialized stacks)
check-full: check tofu-validate-all
    @echo "Full validation complete!"

# Full development cycle: check + build
dev: check nix-build
    @echo "Development build complete!"

# Show current environment configuration
info:
    @echo "Environment Configuration"
    @echo "========================="
    @echo "ENV:           {{env}}"
    @echo "Kube Context:  {{kube_context}}"
    @echo "Ingress:       {{ingress_domain}}"
    @echo "GitLab API:    {{gitlab_api}}"
    @echo "Project ID:    {{gitlab_project}}"

# =============================================================================
# Nix Commands
# =============================================================================

# Build Nix flake (default package)
nix-build:
    nix build

# Build OCI container image
nix-build-container:
    nix build .#container

# Build all Nix outputs
nix-build-all:
    nix build .#attic-client
    nix build .#attic-server
    nix build .#container
    nix build .#attic-gc-image

# Run Nix flake check (all validations)
nix-check:
    nix flake check

# Update flake inputs
nix-update:
    nix flake update

# Show flake outputs
nix-show:
    nix flake show

# Enter development shell (if not using direnv)
nix-shell:
    nix develop

# Format Nix files
nix-fmt:
    nix fmt

# =============================================================================
# OpenTofu Commands (Stack-Level)
# =============================================================================

# Initialize a tofu stack
tofu-init stack:
    #!/usr/bin/env bash
    set -euo pipefail
    cd tofu/stacks/{{stack}}

    echo "=== Initializing {{stack}} ({{env}}) ==="

    # Determine state name based on stack and environment
    case "{{stack}}" in
        attic)
            STATE_NAME=$([ "{{env}}" = "beehive" ] && echo "attic-local" || echo "attic-staging")
            ;;
        gitlab-runners)
            STATE_NAME="gitlab-runners-{{env}}"
            ;;
        *)
            STATE_NAME="{{stack}}-{{env}}"
            ;;
    esac

    if [ -z "${TF_HTTP_PASSWORD:-}" ]; then
        echo "WARNING: TF_HTTP_PASSWORD not set (required for GitLab state backend)"
        echo "For local development, run: export TF_HTTP_PASSWORD='glpat-...'"
    fi

    tofu init -reconfigure \
        -backend-config="address={{gitlab_api}}/projects/{{gitlab_project}}/terraform/state/${STATE_NAME}" \
        -backend-config="lock_address={{gitlab_api}}/projects/{{gitlab_project}}/terraform/state/${STATE_NAME}/lock" \
        -backend-config="unlock_address={{gitlab_api}}/projects/{{gitlab_project}}/terraform/state/${STATE_NAME}/lock" \
        -backend-config="lock_method=POST" \
        -backend-config="unlock_method=DELETE" \
        -backend-config="username=gitlab-ci-token" \
        -backend-config="password=${TF_HTTP_PASSWORD:-}"

# Plan a tofu stack
tofu-plan stack:
    #!/usr/bin/env bash
    set -euo pipefail
    cd tofu/stacks/{{stack}}

    TFVARS="{{env}}.tfvars"

    echo "=== Planning {{stack}} ({{env}}) ==="
    echo "Using tfvars: ${TFVARS}"

    if [ ! -f "${TFVARS}" ]; then
        echo "ERROR: ${TFVARS} not found in tofu/stacks/{{stack}}"
        exit 1
    fi

    tofu plan \
        -var="cluster_context={{kube_context}}" \
        -var-file="${TFVARS}" \
        -out=tfplan

    echo ""
    echo "Plan saved to: tofu/stacks/{{stack}}/tfplan"
    echo "Run 'just tofu-apply {{stack}}' to apply"

# Apply a tofu stack (uses saved plan)
tofu-apply stack:
    #!/usr/bin/env bash
    set -euo pipefail
    cd tofu/stacks/{{stack}}

    if [ ! -f tfplan ]; then
        echo "ERROR: No plan file found. Run 'just tofu-plan {{stack}}' first."
        exit 1
    fi

    echo "=== Applying {{stack}} ({{env}}) ==="
    tofu apply tfplan

# Plan and apply in one step
tofu-deploy stack: (tofu-init stack) (tofu-plan stack) (tofu-apply stack)

# Destroy a tofu stack (with confirmation)
tofu-destroy stack:
    #!/usr/bin/env bash
    set -euo pipefail
    cd tofu/stacks/{{stack}}

    TFVARS="{{env}}.tfvars"

    echo "WARNING: This will destroy all resources in {{stack}} ({{env}})!"
    read -p "Type 'yes' to confirm: " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi

    tofu destroy \
        -var="cluster_context={{kube_context}}" \
        -var-file="${TFVARS}"

# Validate all tofu modules and stacks
tofu-validate-all:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Validating OpenTofu configurations ==="

    ERRORS=0

    # Validate modules (syntax only - providers need init)
    # Modules are validated via stacks that use them
    echo "Checking module syntax..."
    for dir in tofu/modules/*/; do
        if [ -f "${dir}main.tf" ]; then
            echo "  Module: $(basename $dir)"
            # Just check HCL syntax, not full validation (needs providers)
            if ! tofu fmt -check "$dir" >/dev/null 2>&1; then
                echo "    WARNING: Format issues detected"
            fi
        fi
    done

    # Validate stacks that have been initialized
    echo ""
    echo "Checking initialized stacks..."
    for dir in tofu/stacks/*/; do
        if [ -f "${dir}main.tf" ]; then
            stack_name=$(basename "$dir")
            if [ -d "${dir}.terraform" ]; then
                echo "  Stack: ${stack_name} (initialized)"
                if ! (cd "$dir" && tofu validate 2>/dev/null); then
                    echo "    ERROR: Validation failed"
                    ERRORS=$((ERRORS + 1))
                fi
            else
                echo "  Stack: ${stack_name} (not initialized - run 'just tofu-init ${stack_name}')"
            fi
        fi
    done

    echo ""
    if [ $ERRORS -gt 0 ]; then
        echo "Validation completed with $ERRORS error(s)"
        exit 1
    fi
    echo "Validation complete!"

# Format all tofu files
tofu-fmt:
    tofu fmt -recursive tofu/

# Check tofu formatting
tofu-fmt-check:
    tofu fmt -recursive -check tofu/

# Show tofu state for a stack
tofu-state stack:
    cd tofu/stacks/{{stack}} && tofu state list

# Refresh tofu state for a stack
tofu-refresh stack:
    #!/usr/bin/env bash
    set -euo pipefail
    cd tofu/stacks/{{stack}}
    TFVARS="{{env}}.tfvars"
    tofu refresh -var="cluster_context={{kube_context}}" -var-file="${TFVARS}"

# =============================================================================
# Bazel Commands
# =============================================================================

# Run Bazel build (all targets)
bazel-build:
    bazel build //...

# Run Bazel tests
bazel-test:
    bazel test //...

# Run Bazel build with CI config (no remote cache)
bazel-build-ci:
    bazel build --config=ci //...

# Run Bazel build with remote cache (for beehive runners)
bazel-build-cached:
    bazel build --config=ci-cached //...

# Clean Bazel outputs
bazel-clean:
    bazel clean

# Clean Bazel outputs including cache
bazel-clean-all:
    bazel clean --expunge

# Show Bazel dependency graph
bazel-graph:
    bazel query 'deps(//...)' --output=graph | dot -Tsvg > build-graph.svg
    @echo "Graph saved to build-graph.svg"

# =============================================================================
# Kubernetes Commands
# =============================================================================

# List pods in a namespace
k8s-pods namespace="attic-cache":
    kubectl get pods -n {{namespace}} -o wide

# Show pod logs
k8s-logs namespace="attic-cache" selector="app.kubernetes.io/name=attic":
    kubectl logs -n {{namespace}} -l {{selector}} -f --tail=100

# Describe pods in a namespace
k8s-describe namespace="attic-cache":
    kubectl describe pods -n {{namespace}}

# Get events in a namespace (sorted by time)
k8s-events namespace="attic-cache":
    kubectl get events -n {{namespace}} --sort-by='.lastTimestamp'

# Port forward to a service
k8s-forward namespace="attic-cache" service="attic" port="8080":
    kubectl port-forward -n {{namespace}} svc/{{service}} {{port}}:8080

# Get all resources in a namespace
k8s-all namespace="attic-cache":
    @echo "=== Pods ==="
    @kubectl get pods -n {{namespace}} 2>/dev/null || echo "No pods"
    @echo ""
    @echo "=== Deployments ==="
    @kubectl get deployments -n {{namespace}} 2>/dev/null || echo "No deployments"
    @echo ""
    @echo "=== StatefulSets ==="
    @kubectl get statefulsets -n {{namespace}} 2>/dev/null || echo "No statefulsets"
    @echo ""
    @echo "=== Services ==="
    @kubectl get services -n {{namespace}} 2>/dev/null || echo "No services"
    @echo ""
    @echo "=== Ingress ==="
    @kubectl get ingress -n {{namespace}} 2>/dev/null || echo "No ingress"
    @echo ""
    @echo "=== PVCs ==="
    @kubectl get pvc -n {{namespace}} 2>/dev/null || echo "No PVCs"

# Check cluster operators (MinIO, CNPG)
k8s-operators:
    @echo "=== MinIO Operator ==="
    @kubectl get pods -n minio-operator 2>/dev/null || echo "Not installed"
    @echo ""
    @echo "=== CNPG Operator ==="
    @kubectl get pods -n cnpg-system 2>/dev/null || echo "Not installed"

# =============================================================================
# GitLab Runners (Shortcut Commands)
# =============================================================================

# Initialize GitLab runners stack
runners-init: (tofu-init "gitlab-runners")

# Plan GitLab runners deployment
runners-plan: (tofu-plan "gitlab-runners")

# Apply GitLab runners deployment
runners-apply: (tofu-apply "gitlab-runners")

# Full deploy cycle for runners
runners-deploy: (tofu-deploy "gitlab-runners")

# Show runner status
runners-status:
    @echo "=== GitLab Runners Status ==="
    @kubectl get pods -n gitlab-runners -l app=gitlab-runner 2>/dev/null || echo "No runner pods found"
    @echo ""
    @kubectl get deployments -n gitlab-runners 2>/dev/null || echo "No deployments"
    @echo ""
    @helm list -n gitlab-runners 2>/dev/null || echo "No helm releases"

# Show runner logs
runners-logs runner="nix-runner":
    kubectl logs -n gitlab-runners -l release={{runner}} -f --tail=100

# =============================================================================
# Attic Cache (Shortcut Commands)
# =============================================================================

# Initialize Attic stack
attic-init: (tofu-init "attic")

# Plan Attic deployment
attic-plan: (tofu-plan "attic")

# Apply Attic deployment
attic-apply: (tofu-apply "attic")

# Full deploy cycle for Attic
attic-deploy: (tofu-deploy "attic")

# Show Attic status
attic-status:
    @echo "=== Attic Cache Status ({{env}}) ==="
    @echo "Namespace: attic-cache"
    @echo ""
    just k8s-all attic-cache

# Run health check script
attic-health endpoint="https://attic-cache.{{ingress_domain}}":
    ./scripts/health-check.sh -e {{endpoint}} -n attic-cache

# =============================================================================
# Formatting Commands
# =============================================================================

# Format all files (Nix + Tofu + shell)
fmt: nix-fmt tofu-fmt
    @echo "All files formatted!"

# Check all formatting
fmt-check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Checking formatting ==="

    # Check Nix formatting
    echo "Checking Nix files..."
    nix fmt -- --check . 2>/dev/null || { echo "Run 'just nix-fmt' to fix"; exit 1; }

    # Check Tofu formatting
    echo "Checking OpenTofu files..."
    tofu fmt -recursive -check tofu/ || { echo "Run 'just tofu-fmt' to fix"; exit 1; }

    echo "All formatting checks passed!"

# =============================================================================
# Security & Linting
# =============================================================================

# Run security scan with Trivy
security-scan:
    @command -v trivy >/dev/null 2>&1 || { echo "Install trivy: brew install trivy"; exit 1; }
    trivy config . --format table

# Run Nix linting (statix + deadnix)
nix-lint:
    @echo "Running statix..."
    statix check .
    @echo "Running deadnix..."
    deadnix .

# =============================================================================
# State Management
# =============================================================================

# List all GitLab Terraform states
state-list:
    @echo "=== Terraform States in Project ==="
    @glab api projects/{{gitlab_project}}/terraform/state 2>/dev/null | \
        jq -r '.[] | "\(.name)\t\(.locked_at // "unlocked")"' | \
        column -t || echo "Run: glab auth login"

# Unlock a stuck state
state-unlock name:
    #!/usr/bin/env bash
    echo "Unlocking state: {{name}}"
    glab opentofu state unlock "{{name}}" 2>/dev/null || \
        curl -X DELETE -H "PRIVATE-TOKEN: ${TF_HTTP_PASSWORD}" \
            "{{gitlab_api}}/projects/{{gitlab_project}}/terraform/state/{{name}}/lock"

# =============================================================================
# Utility Commands
# =============================================================================

# Clean up generated files
clean:
    rm -rf result result-* graph.svg build-graph.svg
    rm -f tofu/stacks/*/tfplan tofu/stacks/*/plan.json tofu/stacks/*/graph.svg
    @echo "Cleaned up generated files"

# Deep clean (includes Bazel + Nix + Terraform)
clean-all: clean bazel-clean
    rm -rf .direnv/
    rm -rf tofu/stacks/*/.terraform/
    @echo "Deep clean complete!"

# Setup git hooks
setup-hooks:
    ./.githooks/setup.sh

# Generate dependency graph for tofu stack
graph stack:
    cd tofu/stacks/{{stack}} && tofu graph | dot -Tsvg > graph.svg
    @echo "Graph saved to tofu/stacks/{{stack}}/graph.svg"

# =============================================================================
# CI Simulation
# =============================================================================

# Run CI checks locally
ci-local: fmt-check nix-check nix-build tofu-validate-all
    @echo ""
    @echo "=== CI checks passed! ==="

# Run CI health check script
ci-health:
    ./scripts/ci-health-check.sh
