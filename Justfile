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
#   just setup              # Set up local development environment
#   just                    # List all commands
#   just check              # Run all validations
#   just cache-plan          # Plan cache platform deployment
#
# Environment Setup:
#   Create .env from .env.example and set TF_HTTP_PASSWORD (GitLab PAT)
#   The .envrc automatically loads .env via direnv (dotenv_if_exists)
#
# Environment Selection:
#   ENV=prod just cache-plan         # Target prod cluster
#   ENV=dev just cache-plan          # Target dev cluster (default)

# Default recipe - list available commands
default:
    @just --list --unsorted

# Set up local development environment
setup:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Setting up local development environment..."
    echo

    # Check for .env file
    if [ ! -f .env ]; then
        echo "Creating .env from .env.example..."
        cp .env.example .env
        echo
        echo "IMPORTANT: Edit .env and set TF_HTTP_PASSWORD to your GitLab PAT"
        echo "  Get your token from: https://gitlab.com/-/user_settings/personal_access_tokens"
        echo "  Required scopes: api, read_repository, write_repository"
        echo
        echo "After setting TF_HTTP_PASSWORD, reload direnv:"
        echo "  direnv allow"
        echo
    else
        echo ".env already exists"
    fi

    # Check TF_HTTP_PASSWORD
    if [ -z "${TF_HTTP_PASSWORD:-}" ]; then
        echo "WARNING: TF_HTTP_PASSWORD not set in .env"
        echo "  Edit .env and add: TF_HTTP_PASSWORD=glpat-your-token-here"
        echo "  Then run: direnv allow"
    else
        echo "TF_HTTP_PASSWORD: configured ✓"
    fi

    echo
    echo "Setup complete! Run 'just' to see available commands."

# =============================================================================
# Configuration
# =============================================================================

# Organization config file location
org_config := "config/organization.yaml"

# Environment (set via ENV variable)
env := env_var_or_default("ENV", "dev")

# GitLab project for state storage (loaded from organization config)
gitlab_project := `yq '.gitlab.project_id' config/organization.yaml`
gitlab_api := `yq '.gitlab.url' config/organization.yaml` + "/api/v4"

# Kubernetes context based on environment (loaded from organization config)
kube_context := `ENV="${ENV:-dev}" && yq ".clusters[] | select(.name == \"$ENV\") | .context" config/organization.yaml 2>/dev/null || echo ""`

# Ingress domain based on environment (loaded from organization config)
ingress_domain := `ENV="${ENV:-dev}" && yq ".clusters[] | select(.name == \"$ENV\") | .domain" config/organization.yaml 2>/dev/null || echo ""`

# SOCKS proxy configuration (optional, loaded from organization config)
socks_host := `yq '.network.proxy_host // ""' config/organization.yaml`
socks_port := `yq '.network.proxy_port // "1080"' config/organization.yaml`
socks_proxy := if socks_host != "" { "socks5h://localhost:" + socks_port } else { "" }

# =============================================================================
# Network Proxy (Optional)
# =============================================================================

# Start SOCKS proxy (configure ssh host in ~/.ssh/config)
proxy-up:
    @if ssh -O check proxy-host 2>/dev/null; then \
        echo "Proxy already running on localhost:{{socks_port}}"; \
    else \
        echo "Starting SOCKS proxy on localhost:{{socks_port}}..."; \
        ssh -fN proxy-host; \
        echo "Proxy up. Use: HTTPS_PROXY={{socks_proxy}} kubectl ..."; \
    fi

# Stop SOCKS proxy
proxy-down:
    @ssh -O exit proxy-host 2>/dev/null && echo "Proxy stopped" || echo "Proxy not running"

# Check SOCKS proxy status
proxy-status:
    @if ssh -O check proxy-host 2>/dev/null; then \
        echo "Proxy: RUNNING on localhost:{{socks_port}}"; \
        echo "Test:  HTTPS_PROXY={{socks_proxy}} curl -sI https://your-service.example.com"; \
    else \
        echo "Proxy: NOT RUNNING"; \
        echo "Start: just proxy-up"; \
    fi

# Run kubectl through SOCKS proxy (auto-starts proxy if needed)
bk *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! ssh -O check proxy-host 2>/dev/null; then
        echo "Starting proxy..." >&2
        ssh -fN proxy-host
    fi
    HTTPS_PROXY={{socks_proxy}} kubectl {{args}}

# Run curl through SOCKS proxy
bcurl *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! ssh -O check proxy-host 2>/dev/null; then
        echo "Starting proxy..." >&2
        ssh -fN proxy-host
    fi
    HTTPS_PROXY={{socks_proxy}} curl {{args}}

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
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Environment Configuration"
    echo "========================="
    echo "ENV:             {{env}}"
    echo "Kube Context:    {{kube_context}}"
    echo "Ingress:         {{ingress_domain}}"
    echo "GitLab API:      {{gitlab_api}}"
    echo "Project ID:      {{gitlab_project}}"
    echo
    echo "Secrets"
    echo "======="
    if [ -f .env ]; then
        echo ".env file:       exists ✓"
    else
        echo ".env file:       missing (run 'just setup')"
    fi
    if [ -n "${TF_HTTP_PASSWORD:-}" ]; then
        echo "TF_HTTP_PASSWORD: configured ✓"
    else
        echo "TF_HTTP_PASSWORD: not set (required for OpenTofu)"
    fi

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
            STATE_NAME="attic-{{env}}"
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

# Run Bazel build with remote cache
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

# Show runner status for a namespace
runners-status namespace="gitlab-runners":
    @echo "=== Runner Status ({{namespace}}) ==="
    @echo ""
    @echo "=== Pods ==="
    @kubectl get pods -n {{namespace}} -o wide 2>/dev/null || echo "No pods found"
    @echo ""
    @echo "=== HPA ==="
    @kubectl get hpa -n {{namespace}} 2>/dev/null || echo "No HPA found"
    @echo ""
    @echo "=== Helm Releases ==="
    @helm list -n {{namespace}} 2>/dev/null || echo "No helm releases"

# Show runner logs
runners-logs runner namespace="gitlab-runners":
    kubectl logs -n {{namespace}} -l release={{runner}} -f --tail=100

# =============================================================================
# Cache Platform (Shortcut Commands)
# =============================================================================
# The 'attic' stack deploys the complete Nix binary cache platform:
#   - CNPG Operator + PostgreSQL cluster (metadata storage)
#   - MinIO Operator + tenant (S3-compatible object storage)
#   - Attic API server (HPA-enabled Nix binary cache)
#   - Attic GC worker (garbage collection)
#   - DNS records, cache init job, warming CronJob
#   - Bazel remote cache (optional)
#
# The stack directory is named 'attic' for state backend compatibility.
# Use 'just tofu-deploy attic' for the generic recipe.

# Initialize cache platform stack (CNPG, MinIO, Attic, DNS)
cache-init: (tofu-init "attic")

# Plan cache platform deployment
cache-plan: (tofu-plan "attic")

# Apply cache platform deployment
cache-apply: (tofu-apply "attic")

# Full deploy cycle for cache platform (init + plan + apply)
cache-deploy: (tofu-deploy "attic")

# Show cache platform status (pods, operators, storage)
cache-status:
    @echo "=== Cache Platform Status ({{env}}) ==="
    @echo "Namespace: attic-cache"
    @echo ""
    just k8s-all attic-cache
    @echo ""
    just k8s-operators

# Run health check against the cache API endpoint
cache-health endpoint="https://attic-cache.{{ingress_domain}}" namespace="attic-cache":
    ./scripts/health-check.sh -u {{endpoint}} -n {{namespace}} -v

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

# Run CI health check (quick mode, no K8s checks)
ci-health endpoint="https://attic-cache.{{ingress_domain}}":
    ./scripts/health-check.sh -u {{endpoint}} -m 5 -d 10 -M 30

# =============================================================================
# Runner Dashboard App
# =============================================================================

# Install app dependencies
app-install:
    cd app && pnpm install

# Run app dev server
app-dev:
    cd app && pnpm dev

# Build app for production
app-build:
    cd app && pnpm build

# Run app tests
app-test:
    cd app && pnpm test

# Run app type check
app-check:
    cd app && pnpm check

# Run app linter
app-lint:
    cd app && pnpm lint

# Build app via Bazel
app-bazel-build:
    bazel build //app:build

# Run app dev server via Bazel
app-bazel-dev:
    bazel run //app:dev

# Build app OCI image via Nix
app-image:
    nix build .#runner-dashboard-image

# Show app status on cluster
app-status:
    @echo "=== Runner Dashboard Status ({{env}}) ==="
    @kubectl get pods -n runner-dashboard -o wide 2>/dev/null || echo "No pods found"
    @echo ""
    @kubectl get ingress -n runner-dashboard 2>/dev/null || echo "No ingress found"

# Initialize runner-dashboard OpenTofu stack
app-init:
    cd tofu/stacks/runner-dashboard && just env={{env}} init

# Plan runner-dashboard deployment
app-plan:
    cd tofu/stacks/runner-dashboard && just env={{env}} plan

# Apply runner-dashboard deployment
app-apply:
    cd tofu/stacks/runner-dashboard && just env={{env}} apply

# Full deploy cycle: build image, push, tofu apply
app-deploy: app-build app-image
    cd tofu/stacks/runner-dashboard && just env={{env}} deploy

# Show runner-dashboard logs
app-logs:
    cd tofu/stacks/runner-dashboard && just env={{env}} logs

# Port-forward runner-dashboard for local testing
app-port-forward:
    cd tofu/stacks/runner-dashboard && just env={{env}} port-forward

# =============================================================================
# Documentation Site
# =============================================================================

# Start docs site dev server
docs-dev:
    cd docs-site && pnpm dev

# Build docs site for production (adapter-static)
docs-build:
    cd docs-site && pnpm build

# Install docs site dependencies
docs-install:
    cd docs-site && pnpm install

# Type-check docs site
docs-check:
    cd docs-site && pnpm check

# =============================================================================
# TeX Research Document
# =============================================================================

# Build research PDF with latexmk
tex:
    #!/usr/bin/env bash
    set -euo pipefail

    TEX_DIR="tex_research/glorious-flywheel"
    TEX_FILE="glorious-flywheel.tex"
    BUILD_DIR="${TEX_DIR}/build"
    DIST_DIR="${TEX_DIR}/dist"

    if ! command -v latexmk &> /dev/null; then
        echo "[tex] latexmk not found. Install via: nix develop"
        exit 0
    fi

    mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

    cd "${TEX_DIR}" && latexmk -pdf -xelatex \
        -interaction=nonstopmode \
        -output-directory=build \
        -shell-escape \
        "${TEX_FILE}" 2>&1 | tail -20 || {
            echo "[tex] Warning: check build/glorious-flywheel.log"
        }

    if [ -f "build/glorious-flywheel.pdf" ]; then
        cp "build/glorious-flywheel.pdf" "dist/"
        echo "[tex] PDF generated: dist/glorious-flywheel.pdf"
    else
        echo "[tex] Warning: PDF not generated"
    fi

# Clean TeX build artifacts
tex-clean:
    rm -rf tex_research/glorious-flywheel/build
    echo "[tex] Build artifacts cleaned"

# Watch and rebuild TeX on changes
tex-watch:
    watchexec -w tex_research/glorious-flywheel -e tex,bib -- just tex

# ============================================================================
# Changelog
# ============================================================================

# Generate CHANGELOG.md from git history
changelog:
    git cliff --output CHANGELOG.md
    echo "[changelog] Generated CHANGELOG.md"

# Preview changelog for next release (dry run)
changelog-preview:
    git cliff --unreleased

# Generate changelog for a specific tag/version
changelog-tag tag:
    git cliff --tag {{tag}} --output CHANGELOG.md
    echo "[changelog] Generated CHANGELOG.md for {{tag}}"
