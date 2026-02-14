# Glorious Flywheel

Self-deploying infrastructure that builds, caches, and monitors itself.

## What is this?

A set of OpenTofu modules, Nix packages, and a SvelteKit monitoring dashboard that
form a recursive infrastructure system for Gitlab.  GitLab runners deploy themselves as a HPA runner pool, the Nix
binary cache caches its own derivations, bazel overlay orchestrates intrer enterprise deployments,
intra enterprise automations (such as your companies pool of autonmous clankers, Steve, RenovateBot or your manager checking in every now and again)
all running on infrastructure managed by this code.  I think its kinda neat.

## Architecture

Two-module Bzlmod architecture: a public upstream repository (this one) and private
overlay repositories that add organization-specific configuration.

```mermaid
graph TD
    subgraph upstream["attic-iac (upstream)"]
        M[MODULE.bazel] --> TOFU[tofu/modules/]
        M --> APP[app/]
        M --> DOCS[docs-site/]
    end
    subgraph overlay["Organization Overlay"]
        BM[MODULE.bazel] -->|"bazel_dep + local_path_override"| M
        BM --> EXT[build/extensions.bzl]
        EXT -->|"symlink merge"| MERGED["@attic_merged"]
    end
```

## Components

- **Attic binary cache** -- S3/MinIO storage, CloudNativePG PostgreSQL, automatic GC
- **GitLab runners** -- 5 types (docker, dind, rocky8, rocky9, nix) with HPA autoscaling
- **Runner dashboard** -- SvelteKit 5 + Skeleton v4 monitoring UI with drift detection
- **Documentation site** -- SvelteKit + mdsvex + Mermaid, deployed to GitHub/GitLab Pages

```mermaid
graph LR
    R[Runners] -->|"tofu apply"| R
    R -->|deploy| AC[Attic Cache]
    AC -->|accelerates| NB[Nix Builds]
    NB -->|"executed by"| R
    R -->|deploy| D[Dashboard]
    D -->|monitors| R
    AC -->|"caches its own derivations"| AC
    RB[Clanker or Human] -->|"version bump PRs"| PIPE[CI Pipeline]
    PIPE -->|"executed by"| R
```

## Quick Start

Prerequisites: Nix with flakes, kubectl, direnv

```bash
# Enter development shell
direnv allow

# Configure your organization
cp config/organization.example.yaml config/organization.yaml
cp .env.example .env
# Edit .env with your GitLab PAT for the state backend

# Deploy stacks in order (each needs a tfvars file in its stack dir)
just tofu-deploy attic
just tofu-deploy gitlab-runners
just tofu-deploy runner-dashboard
```

`tofu-deploy` runs init, plan, and apply. Each stack expects a
`dev.tfvars` in `tofu/stacks/<stack>/` with your cluster-specific
values. See [Getting Started](docs/getting-started-guide.md) for the
full walkthrough, or [Create Your First Overlay](docs/infrastructure/overlay-creation.md)
for production deployments.

## Project Structure

```
attic-iac/
  app/                  # Runner dashboard (SvelteKit 5 + Skeleton v4)
  docs/                 # Documentation (Mermaid diagrams, no ASCII art)
  docs-site/            # Documentation site (SvelteKit + mdsvex + adapter-static)
  tex_research/         # Research document (LaTeX)
  tofu/
    modules/            # Reusable OpenTofu modules
    stacks/             # Deployment stacks
  config/               # Organization configuration
  k8s/                  # Kubernetes manifests
  nix/                  # Nix packaging
  build/                # Bazel overlay system
  scripts/              # Build and deploy scripts
```

## Documentation

Full documentation is available at the [docs site](https://jesssullivan.github.io/attic-iac/)
or in [docs/](docs/index.md).

Key topics:
- [Recursive Dogfooding](docs/architecture/recursive-dogfooding.md) -- the core concept
- [Bzlmod Topology](docs/architecture/bzlmod-topology.md) -- two-module system
- [Greedy Build Pattern](docs/build-system/greedy-build-pattern.md) -- build fast, cache everything
- [Runner Selection](docs/runners/runner-selection.md) -- which runner to use
- [OpenTofu Modules](docs/reference/tofu-modules.md) -- all modules documented

## Development

```bash
just dev               # Start dashboard dev server
just docs-dev          # Start docs site dev server
just check             # Run all validations
just app-test          # Run dashboard tests
just tex               # Build research PDF
```

## Creating an Overlay

To deploy attic-iac for your organization, create a private overlay repository:

1. Clone upstream as a sibling directory (`~/git/attic-iac`)
2. Create your overlay repo with `MODULE.bazel` declaring `bazel_dep(name = "attic-iac")`
3. Add `build/overlay.bzl` and `build/extensions.bzl` for symlink-merge
4. Add `config/organization.yaml` and per-stack tfvars files
5. Set up a CI pipeline that clones upstream and runs tofu plan/apply
6. Push to main and let CI deploy

**New to overlays?** Follow the complete walkthrough:
[Create Your First Overlay](docs/infrastructure/overlay-creation.md)

For the architecture behind the overlay system, see
[docs/architecture/overlay-system.md](docs/architecture/overlay-system.md).

## License

Zlib
