# GloriousFlywheel (attic-iac)

Self-deploying infrastructure that builds, caches, and monitors itself.

```mermaid
graph LR
    R[Runners] -->|"tofu apply"| R
    R -->|deploy| AC[Attic Cache]
    AC -->|accelerates| NB[Nix Builds]
    NB -->|"executed by"| R
    R -->|deploy| D[Dashboard]
    D -->|monitors| R
    AC -->|"caches its own derivations"| AC
    RB[RenovateBot] -->|"version bump PRs"| PIPE[CI Pipeline]
    PIPE -->|"executed by"| R
```

## What is this?

A set of OpenTofu modules, Nix packages, and a SvelteKit monitoring dashboard that
form a recursive infrastructure system. GitLab runners deploy themselves, the Nix
binary cache caches its own derivations, and RenovateBot keeps dependencies current --
all running on infrastructure managed by this code.

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

## Quick Start

Prerequisites: Nix with flakes, kubectl, direnv

```bash
# Enter development shell
direnv allow

# Configure your organization
cp config/organization.example.yaml config/organization.yaml

# Set up secrets
cp .env.example .env
# Add TF_HTTP_PASSWORD (GitLab PAT)

# Deploy
just tofu-plan attic
just tofu-apply attic
```

See [docs/infrastructure/quick-start.md](docs/infrastructure/quick-start.md) for the
full deployment guide.

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

To deploy attic-iac for your organization:

1. Create a new repository with `MODULE.bazel` declaring `bazel_dep(name = "attic-iac")`
2. Add `local_path_override(path = "../attic-iac")` for local development
3. Create `build/extensions.bzl` to merge upstream with your overrides
4. Add organization-specific `config/organization.yaml` and stack tfvars
5. Set up CI pipeline that clones upstream and runs tofu plan/apply

See [docs/architecture/overlay-system.md](docs/architecture/overlay-system.md) for details.

## License

Apache 2.0
