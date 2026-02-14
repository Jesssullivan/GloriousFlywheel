---
title: Getting Started
order: 1
---

# Getting Started

This guide walks you through deploying GloriousFlywheel infrastructure for your organization, from zero to a running Nix cache, GitLab runner pool, and monitoring dashboard.

## Decide: Direct or Overlay?

There are two ways to deploy:

| Approach | When to Use | What You Get |
|----------|-------------|--------------|
| **Direct** | Evaluating, single cluster, no private config | Clone upstream, add `organization.yaml`, deploy |
| **Overlay** | Production, multiple clusters, private secrets, CI/CD | Your own repo layered on top of upstream |

**Most organizations should use an overlay.** It keeps your secrets, tfvars, and CI pipeline in a private repo while pulling shared modules from upstream. See [Create Your First Overlay](infrastructure/overlay-creation.md) for a step-by-step walkthrough.

If you just want to try things out, the direct approach works fine -- you can always migrate to an overlay later.

## Prerequisites

You need three things installed on your workstation:

1. **Nix** with flakes enabled
2. **direnv** (optional but recommended)
3. **kubectl** access to a Kubernetes cluster

### Install Nix

```bash
# Official installer (Linux / macOS)
curl -L https://nixos.org/nix/install | sh

# Enable flakes (add to ~/.config/nix/nix.conf)
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### Install direnv

```bash
# macOS
brew install direnv

# Nix
nix profile install nixpkgs#direnv

# Add hook to your shell (~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish)
eval "$(direnv hook bash)"    # bash
eval "$(direnv hook zsh)"     # zsh
direnv hook fish | source     # fish
```

### Kubernetes Access

You need a kubeconfig file that can reach your target cluster. The cluster should be running Kubernetes 1.28+ with:

- A default `StorageClass` for persistent volumes
- Ingress controller (Traefik, nginx, or similar)
- Optional: cert-manager for TLS, Prometheus for monitoring

## Direct Deployment

### 1. Clone and enter the devShell

```bash
git clone https://github.com/Jesssullivan/GloriousFlywheel.git ~/git/attic-iac
cd ~/git/attic-iac
direnv allow  # or: nix develop
```

The devShell provides pinned versions of `tofu`, `kubectl`, `pnpm`, `node`, and other tools. You don't need to install them separately.

### 2. Configure your organization

```bash
cp config/organization.example.yaml config/organization.yaml
```

Edit `organization.yaml` with your cluster details. At minimum, set:

```yaml
organization:
  name: your-org

clusters:
  - name: dev
    role: development
    domain: dev.example.com
    context: your-kubeconfig-context

namespaces:
  attic:
    dev: attic-cache-dev
  runners:
    all: gitlab-runners
```

See the [Customization Guide](infrastructure/customization-guide.md) for all fields.

### 3. Set up secrets

```bash
cp .env.example .env
```

Edit `.env` and set the `TF_HTTP_` credentials to a GitLab Personal Access Token with `api` scope (see `.env.example` for the required variable names). This token is used for the OpenTofu state backend.

### 4. Deploy the three stacks (in order)

```bash
# 1. Cache platform (must be first -- deploys CNPG, MinIO, PostgreSQL,
#    Attic API, GC worker, and DNS. Runners reference the cache endpoint.)
just tofu-plan attic
just tofu-apply attic

# 2. GitLab runners
just tofu-plan gitlab-runners
just tofu-apply gitlab-runners

# 3. Runner dashboard
just tofu-plan runner-dashboard
just tofu-apply runner-dashboard
```

### 5. Verify

```bash
kubectl get pods -n attic-cache-dev       # Attic API + PostgreSQL + MinIO
kubectl get pods -n gitlab-runners        # 5 runner manager pods
kubectl get pods -n runner-dashboard      # Dashboard pod
```

Check GitLab: **Your Group > Settings > CI/CD > Runners** should show the registered runners.

## Overlay Deployment

For production use, create an overlay repository. This keeps your secrets and configuration private while pulling shared modules from upstream.

**Follow the full walkthrough:** [Create Your First Overlay](infrastructure/overlay-creation.md)

The short version:

1. Create a private GitLab repo for your overlay
2. Clone upstream as a sibling directory
3. Add `MODULE.bazel`, `build/overlay.bzl`, `build/extensions.bzl`
4. Add your `config/organization.yaml` and tfvars files
5. Set up a CI pipeline that clones upstream and runs tofu plan/apply
6. Push to main and let CI deploy

## What Gets Deployed

After a successful deployment, you have:

```
Kubernetes Cluster
  cnpg-system/
    cnpg-controller-manager (CloudNativePG operator)
  minio-operator/
    minio-operator (MinIO operator)
  attic-cache-dev/
    atticd (Nix binary cache API, HPA-enabled)
    attic-gc (garbage collection worker)
    attic-pg (PostgreSQL cluster via CNPG)
    attic-minio (S3-compatible object storage via MinIO)
    attic-init-cache (one-shot cache initialization job)
    attic-cache-warm (daily cache warming CronJob)
  gitlab-runners/
    docker-runner (general purpose CI)
    dind-runner (Docker-in-Docker builds)
    rocky8-runner (RHEL 8 packaging)
    rocky9-runner (RHEL 9 packaging)
    nix-runner (Nix builds + Attic cache)
  runner-dashboard/
    dashboard (SvelteKit monitoring UI)
```

The runners are registered at your GitLab group level. Any project in the group can use them by adding `tags:` to their `.gitlab-ci.yml`:

```yaml
build:
  tags: [docker]
  script:
    - make build
```

## Next Steps

- [Self-Service Enrollment](runners/self-service-enrollment.md) -- how project teams use the runners
- [Project Onboarding](runners/project-onboarding.md) -- step-by-step for enrolling a project
- [Runner Selection Guide](runners/runner-selection.md) -- which runner type for which workload
- [Customization Guide](infrastructure/customization-guide.md) -- full `organization.yaml` reference
- [Architecture Overview](architecture/recursive-dogfooding.md) -- understand the recursive flywheel
