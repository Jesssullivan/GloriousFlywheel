# Recursive Dogfooding: Self-Deploying Infrastructure

## The Pattern

The attic-iac infrastructure exhibits a rare and elegant property: **it deploys itself**. The runners, caches, and dashboard form a closed loop where each component participates in its own deployment and the deployment of every other component.

```
┌─────────────────────────────────────────────────────────────────┐
│                         GitLab CI/CD                            │
│                                                                 │
│   push to main ──► pipeline triggers ──► jobs dispatched        │
│                                                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              Beehive Kubernetes Cluster                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  bates-ils-runners (self-hosted GitLab runners)          │   │
│  │                                                          │   │
│  │   bates-docker ──┐                                       │   │
│  │   bates-dind   ──┤                                       │   │
│  │   bates-rocky8 ──┼── execute CI jobs that deploy ──┐     │   │
│  │   bates-rocky9 ──┤   all three namespaces           │     │   │
│  │   bates-nix    ──┘                                  │     │   │
│  └──────────────────────────────────────┬──────────────┘     │
│                                         │                     │
│              ┌──────────────────────────┼────────────┐       │
│              ▼                          ▼            ▼       │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────┐  │
│  │  attic-cache-dev  │  │  bates-ils-      │  │  runner-  │  │
│  │  (Nix binary      │  │  runners         │  │  dashboard│  │
│  │   cache)          │  │  (themselves!)    │  │  (SvelteKit│  │
│  └────────┬─────────┘  └──────────────────┘  │   monitor) │  │
│           │                                   └───────────┘  │
│           │  nix build cache hits                             │
│           └──────────────────────────────────────────────────│
│                    ▲                                          │
│                    │ push derivations during CI               │
│                    └──────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────────┘
```

## What Makes It Recursive

### 1. Runners Deploy Themselves

The `bates-ils-runners` namespace contains 5 GitLab runner pods. When the CI pipeline runs `deploy:runners:beehive`, one of those same runners picks up the job and applies the OpenTofu plan that manages its own deployment, HPA scaling rules, RBAC, and configuration.

A runner literally executes `tofu apply` on the manifest that defines its own existence.

### 2. The Nix Cache Caches Its Own Build

The Attic binary cache at `attic-cache.beehive.bates.edu` stores Nix derivations. When the `bates-nix` runner builds Nix packages in CI, it pushes results to this cache. The Attic server itself is built with Nix, deployed by tofu, and its derivations are stored in... itself.

The `watch-store` pattern (see [greedy-build-pattern.md](greedy-build-pattern.md)) makes this even tighter: derivations stream into the cache as they're built, so even partial builds contribute to the cache that accelerates the next build.

### 3. The Dashboard Monitors Its Own Deployment

The runner dashboard at `runner-dashboard.beehive.bates.edu` displays the status of the runners that deploy it. When `deploy:dashboard:beehive` runs, you can watch the dashboard show the runner executing the job that will restart the dashboard.

### 4. The Bazel Cache Accelerates Its Own Builds

Bazel's disk cache and remote cache (when configured) store build artifacts for the SvelteKit dashboard app, tofu validation, and configuration tests. Each CI run populates the cache that makes the next CI run faster — including the run that deploys the cache infrastructure.

## The Full Dependency Cycle

```
Runners ──deploy──► Attic Cache ──accelerates──► Nix Builds
   ▲                                                  │
   │                                                  │
   └──── runners execute nix build jobs ◄─────────────┘

Runners ──deploy──► Dashboard ──monitors──► Runners
   ▲                                          │
   │                                          │
   └──── runners visible in dashboard ◄───────┘

Runners ──deploy──► Runners (direct self-reference)
```

Every arrow in this graph is a real runtime dependency, not a conceptual one. The system has bootstrapped itself into a stable fixed point.

## Why This Matters

### Confidence Through Eating Your Own Cooking

If the runner infrastructure breaks, the pipeline that would fix it can't run. This creates strong evolutionary pressure: the infrastructure *must* be reliable because its own maintenance depends on it. Fragile configurations get caught immediately because they block their own repair.

### Single Pane of Glass

The dashboard, deployed by the runners, showing the runners, accelerated by the cache, deployed by the runners — it's all one system. There's no external orchestrator, no separate CI service, no out-of-band deployment mechanism. The system is self-contained.

### Incremental Trust

The bootstrap sequence is:
1. First deploy: manual `tofu apply` from a laptop (one-time)
2. Second deploy: CI pipeline on SaaS runners (external bootstrap)
3. Third deploy onward: self-hosted runners deploy themselves

Each iteration increases the system's autonomy. After bootstrap, the only external dependency is GitLab.com's API (for git push and runner coordination).

## Bootstrap and Recovery

### Initial Bootstrap

The first deployment must come from outside the system (you can't use runners that don't exist yet). This is a one-time `tofu apply` from a developer workstation through a SOCKS proxy to the cluster.

### Recovery from Total Failure

If all runners go down simultaneously:
1. GitLab CI falls back to SaaS shared runners (always available)
2. SaaS runners execute the pipeline that redeploys self-hosted runners
3. Self-hosted runners come back online and resume self-management

The `kubernetes` tag is shared between self-hosted and SaaS runners, providing automatic failover. This is deliberate — the system degrades gracefully rather than entering an unrecoverable state.

### The Attic Cache Bootstrap

The Nix cache has its own chicken-and-egg: `attic watch-store` needs the `attic` binary, which is built by Nix, which benefits from the cache that `watch-store` populates. The solution (documented in [greedy-build-pattern.md](greedy-build-pattern.md)) uses `--max-jobs 0` to attempt a cache-only fetch of the attic client. First build: no watch-store, end-of-build push. Every subsequent build: watch-store active, incremental push.

## Overlay Architecture and Recursion

The upstream/overlay split adds another layer: the upstream `attic-iac` repo defines the generic infrastructure modules. The Bates overlay provides org-specific configuration (tfvars, organization.yaml, CI variables). The overlay CI pipeline clones the upstream, symlinks modules, and applies — using runners deployed by a previous run of the same pipeline.

This means a change to the upstream runner module flows through:
1. Push to `attic-iac` on GitHub
2. Next overlay pipeline run picks up new upstream code
3. Self-hosted runners apply the change to their own definitions
4. Runners restart with the new configuration
5. Next pipeline run uses the updated runners

The entire propagation is automatic. Push to upstream, wait, and the system converges.
