---
title: Runner Selection Guide
order: 10
---

# Runner Selection Guide

Choose the smallest runner that meets the requirements of your CI job.
Lighter runners start faster and consume fewer cluster resources.

## Decision Tree

```mermaid
graph TD
    START[New CI Job] -->|"Need Docker?"| Q1{Docker builds?}
    Q1 -->|Yes| DIND[dind runner]
    Q1 -->|No| Q2{RHEL packages?}
    Q2 -->|"RHEL 8"| R8[rocky8 runner]
    Q2 -->|"RHEL 9"| R9[rocky9 runner]
    Q2 -->|No| Q3{Reproducible?}
    Q3 -->|Yes| NIX[nix runner]
    Q3 -->|No| DOCKER[docker runner]
```

## Guidelines

- **Default choice**: `docker`. Lightweight Alpine base with the fastest
  startup time. Suitable for most CI jobs that do not have special
  requirements.
- **Need Docker builds?** Use `dind`. This runner is privileged and provides
  a Docker-in-Docker sidecar. See [Docker Builds](docker-builds.md) for
  configuration details.
- **Need RHEL packages?** Use `rocky8` or `rocky9`, matching the target
  operating system version. These runners provide `dnf` and glibc at the
  version your packages expect.
- **Need reproducible builds?** Use `nix`. Flakes are enabled and the Attic
  binary cache is pre-configured. See [Nix Builds](nix-builds.md) for the
  recommended pipeline pattern.

## Runner Tags

Use these tags in your `.gitlab-ci.yml` to select a runner:

| Runner | Tags |
|--------|------|
| docker | `docker` |
| dind | `dind`, `privileged` |
| rocky8 | `rocky8` |
| rocky9 | `rocky9` |
| nix | `nix`, `flakes` |

## Performance Tip

Always use the smallest runner that meets your needs. The `docker` runner
has the lowest overhead and fastest pod scheduling. Reserve `dind` for jobs
that genuinely require a Docker daemon, and `nix` for jobs that benefit from
Nix's reproducibility guarantees and binary cache.
