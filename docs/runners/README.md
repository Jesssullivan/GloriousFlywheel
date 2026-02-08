---
title: Runners Overview
order: 1
---

# Runners Overview

This project deploys five GitLab CI runner types on Kubernetes via the
GitLab Runner Helm chart. Each runner targets a specific workload profile.
All runners are managed by the `gitlab-runner` OpenTofu module and configured
through `organization.yaml`.

## Runner Types

| Runner | Base Image | Privileged | Docker Builds | Package Manager | Use Case |
|--------|-----------|------------|---------------|-----------------|----------|
| docker | Alpine | No | No | apk | General CI jobs |
| dind | Alpine + Docker | Yes | Yes | apk | Container builds |
| rocky8 | Rocky Linux 8 | No | No | dnf (glibc 2.28) | RHEL 8 compatibility |
| rocky9 | Rocky Linux 9 | No | No | dnf (glibc 2.34) | RHEL 9 compatibility |
| nix | NixOS | No | No | nix | Reproducible builds |

## Common Properties

- **Deployment method**: Kubernetes-deployed via the GitLab Runner Helm chart.
- **Autoscaling**: Each runner type has an independent HorizontalPodAutoscaler
  configured for 1--5 replicas, with a 15-second scale-up stabilization window
  and a 5-minute scale-down stabilization window.
- **Nix integration**: Nix runners auto-configure the `ATTIC_SERVER` and
  `ATTIC_CACHE` environment variables for transparent binary cache access.
- **Infrastructure**: Deployed via the `gitlab-runner` OpenTofu module in
  `tofu/modules/gitlab-runner/`.

## Further Reading

- [Runner Selection Guide](runner-selection.md) -- how to choose the right runner
- [Docker Builds](docker-builds.md) -- Docker-in-Docker configuration
- [Nix Builds](nix-builds.md) -- Nix flake and Attic cache patterns
- [HPA Tuning](hpa-tuning.md) -- autoscaler configuration
- [Security Model](security-model.md) -- privilege and access boundaries
- [Troubleshooting](troubleshooting.md) -- common issues and fixes
- [Runbook](runbook.md) -- operational procedures
