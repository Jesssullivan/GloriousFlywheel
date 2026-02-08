---
title: Security Model
order: 50
---

# Security Model

This document describes the security boundaries and access controls for the
runner infrastructure.

## Privilege Boundary

Only the `dind` runner operates in privileged mode. This is required for the
Docker daemon sidecar and cannot be avoided for Docker-in-Docker builds. All
other runner types (`docker`, `rocky8`, `rocky9`, `nix`) run as unprivileged
containers.

For container builds that do not require a full Docker daemon, consider using
Kaniko on the unprivileged `docker` runner instead. See
[Docker Builds](docker-builds.md) for details.

## Namespace Isolation

All runners are deployed into a dedicated namespace: `bates-ils-runners`.
This isolates runner workloads from application services and other
infrastructure components.

## RBAC

Runners have minimal RBAC permissions scoped to their own namespace. They
cannot create, modify, or delete resources outside `bates-ils-runners`.
The GitLab Runner Helm chart creates a ServiceAccount with only the
permissions needed to manage job pods within the namespace.

## Secrets Management

- **Runner registration token**: Stored as a Kubernetes Secret in the
  `bates-ils-runners` namespace. Created and managed by the `gitlab-runner`
  OpenTofu module.
- **Attic credentials**: Nix runners receive Attic connection details via
  environment variables injected from Kubernetes Secrets.
- **No secrets in CI variables**: Sensitive values are managed through
  Kubernetes Secrets and OpenTofu, not GitLab CI/CD variable settings where
  possible.

## Network Access

- Runners can reach the Attic cache server in the `attic-cache-dev`
  namespace for binary cache operations.
- Runners can reach external registries for pulling container images.
- Runners do not have write access to any container registry by default.
  Push access must be configured explicitly per job via CI/CD credentials.

## Container Images

Runner job pods pull images from public registries (Docker Hub, GitLab
Container Registry). The runners themselves do not have push access to any
registry. Image provenance is determined by the base image specified in the
runner configuration (Alpine, Rocky Linux, NixOS).
