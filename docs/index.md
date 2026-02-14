---
title: GloriousFlywheel
order: 0
---

# GloriousFlywheel

Self-deploying infrastructure that builds, caches, and monitors itself.

## What is this?

attic-iac is a set of OpenTofu modules, Nix packages, and a SvelteKit dashboard that
together form a self-improving infrastructure system. The core insight is recursive
dogfooding: the CI runners deploy themselves, the Nix cache caches its own derivations,
and RenovateBot keeps everything up to date -- all running on infrastructure managed by
the same code.

## Architecture

The system uses a two-module Bzlmod architecture. A public upstream repository
([attic-iac](architecture/bzlmod-topology.md)) contains all reusable modules. Private
overlay repositories add organization-specific configuration and deploy to their own
clusters.

- [Recursive Dogfooding](architecture/recursive-dogfooding.md) -- the core concept
- [Bzlmod Topology](architecture/bzlmod-topology.md) -- two-module system
- [Overlay System](architecture/overlay-system.md) -- how overlays merge with upstream
- [Multi-Repo Layout](architecture/multi-repo-layout.md) -- three-repo topology
- [RenovateBot Flywheel](architecture/renovatebot-flywheel.md) -- self-improving cycle

## Getting Started

- [Getting Started Guide](getting-started-guide.md) -- first-time user journey
- [Create Your First Overlay](infrastructure/overlay-creation.md) -- step-by-step overlay setup
- [Quick Start](infrastructure/quick-start.md) -- deploy from zero
- [Customization Guide](infrastructure/customization-guide.md) -- configure for your org
- [Clusters and Environments](infrastructure/clusters-and-environments.md) -- cluster layout

## Build System

- [Greedy Build Pattern](build-system/greedy-build-pattern.md) -- build fast, cache everything
- [Watch-Store Bootstrap](build-system/watch-store.md) -- incremental Nix cache
- [Container Builds](build-system/containers.md) -- nix2container, Dockerfile, rules_img
- [Bazel Targets](build-system/bazel-targets.md) -- all build targets

## Runners

- [Overview](runners/README.md) -- 5 runner types
- [Selection Guide](runners/runner-selection.md) -- which runner to use
- [Runbook](runners/runbook.md) -- operational procedures

## CI/CD

- [Pipeline Overview](ci-cd/pipeline-overview.md) -- 4-stage pipeline
- [Overlay Pipelines](ci-cd/overlay-pipelines.md) -- how overlays extend CI
- [Deployment Flow](ci-cd/deployment-flow.md) -- commit to production

## Reference

- [OpenTofu Modules](reference/tofu-modules.md) -- all modules documented
- [Configuration Reference](reference/config-reference.md) -- organization.yaml schema
- [Environment Variables](reference/environment-variables.md) -- all env vars
- [Justfile Commands](reference/justfile-commands.md) -- all just recipes
