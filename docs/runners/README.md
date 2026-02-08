# GitLab Runners

Unified auto-scaling GitLab Runner infrastructure for Kubernetes.

## Overview

This infrastructure provides self-hosted GitLab Runners on Kubernetes clusters, supporting various workload types for CI/CD pipelines.

## Available Runners

| Runner     | Tags                           | Use Case                        | Default Image        |
| ---------- | ------------------------------ | ------------------------------- | -------------------- |
| **docker** | `docker`, `linux`, `amd64`     | Standard builds, scripts, tests | `alpine:3.21`        |
| **dind**   | `docker`, `dind`, `privileged` | Container builds, docker push   | `docker:27-dind`     |
| **rocky8** | `rocky8`, `rhel8`, `linux`     | RHEL 8 compatibility testing    | `rockylinux:8`       |
| **rocky9** | `rocky9`, `rhel9`, `linux`     | RHEL 9 compatibility testing    | `rockylinux:9`       |
| **nix**    | `nix`, `flakes`                | Nix builds with Attic cache     | `nixpkgs/nix-flakes` |

## Quick Start

### Using in Your Project

Add a `.gitlab-ci.yml` to your project:

```yaml
stages:
  - build
  - test
  - deploy

# Standard Alpine-based job
build-app:
  stage: build
  tags:
    - docker
    - linux
  script:
    - apk add --no-cache nodejs npm
    - npm install
    - npm run build

# Docker build job
build-image:
  stage: build
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    - docker build -t myapp:latest .
    - docker push $CI_REGISTRY_IMAGE:latest

# RHEL 8 compatibility test
test-rhel8:
  stage: test
  tags:
    - rocky8
  script:
    - dnf install -y python3 python3-pip
    - pip3 install ansible
    - ansible-playbook test.yml

# Nix build with Attic cache
build-nix:
  stage: build
  tags:
    - nix
    - flakes
  script:
    - nix build .#default
    - nix flake check
```

## Runner Selection Guide

### When to Use Each Runner

**bates-docker** (Standard)

- General purpose builds and tests
- Scripts and automation
- Lightweight workloads
- Default choice for most jobs

**bates-dind** (Docker-in-Docker)

- Building container images
- Pushing to registries
- Running docker-compose
- Container integration tests

**bates-rocky8** (RHEL 8)

- Testing RHEL 8 compatibility
- Building RPM packages
- Running Ansible against RHEL 8
- Legacy application testing (glibc 2.28)

**bates-rocky9** (RHEL 9)

- Testing RHEL 9 compatibility
- Modern RHEL development
- cgroups v2 testing
- Current production environment (glibc 2.34)

**bates-nix** (Nix)

- Reproducible builds with Nix
- Flakes-based projects
- Cross-compilation
- Builds automatically cached to Attic

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitLab.com (bates-ils group)                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS (GitLab K8s Agent)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Beehive Kubernetes Cluster                       │
│                                                                  │
│  Namespace: bates-ils-runners                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Runner Manager Pods (with HPA)                 │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───┐ │ │
│  │  │ docker   │ │  dind    │ │ rocky8   │ │ rocky9   │ │nix│ │ │
│  │  │ manager  │ │ manager  │ │ manager  │ │ manager  │ │mgr│ │ │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └─┬─┘ │ │
│  └───────┼────────────┼────────────┼────────────┼─────────┼───┘ │
│          │            │            │            │         │     │
│          ▼            ▼            ▼            ▼         ▼     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Job Pods (Ephemeral, per CI job)               │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  HPA ──► Scale based on CPU/Memory ──► 1-5 replicas per type    │
└─────────────────────────────────────────────────────────────────┘
```

## Auto-Scaling (HPA)

Runners automatically scale based on workload:

| Runner | Min Replicas | Max Replicas | Scale Up   | Scale Down  |
| ------ | ------------ | ------------ | ---------- | ----------- |
| docker | 1            | 5            | 15s window | 5min window |
| dind   | 1            | 3            | 15s window | 5min window |
| rocky8 | 1            | 3            | 15s window | 5min window |
| rocky9 | 1            | 3            | 15s window | 5min window |
| nix    | 1            | 3            | 15s window | 5min window |

Scaling triggers:

- **Scale up**: CPU > 70% or Memory > 80%
- **Scale down**: After 5 minutes of reduced load

## Resource Limits

### Manager Pods (per runner type)

| Resource       | docker | dind  | rocky | nix   |
| -------------- | ------ | ----- | ----- | ----- |
| CPU Request    | 100m   | 200m  | 100m  | 100m  |
| CPU Limit      | 500m   | 1     | 500m  | 500m  |
| Memory Request | 128Mi  | 256Mi | 128Mi | 128Mi |
| Memory Limit   | 512Mi  | 1Gi   | 512Mi | 512Mi |

### Job Pods (per CI job)

| Resource       | docker | dind | rocky | nix  |
| -------------- | ------ | ---- | ----- | ---- |
| CPU Request    | 100m   | 500m | 100m  | 500m |
| CPU Limit      | 2      | 4    | 2     | 4    |
| Memory Request | 256Mi  | 1Gi  | 256Mi | 1Gi  |
| Memory Limit   | 2Gi    | 8Gi  | 2Gi   | 8Gi  |

## Nix + Attic Integration

The Nix runner is pre-configured with [Attic](https://github.com/zhaofengli/attic) binary cache integration:

```yaml
build-with-cache:
  tags:
    - nix
  script:
    # Attic is automatically configured
    - nix build .#mypackage
    # Push to cache (if ATTIC_TOKEN is set)
    - attic push main result
```

Environment variables available:

- `ATTIC_SERVER`: `https://attic-cache.beehive.bates.edu`
- `ATTIC_CACHE`: `main`

## Deployment

### Prerequisites

1. GitLab group access token with `create_runner` scope
2. Kubernetes context configured for Beehive cluster
3. OpenTofu installed

### Deploy Runners

```bash
cd tofu/stacks/bates-ils-runners

# Set environment variables
export TF_HTTP_PASSWORD=<your-gitlab-pat>
export TF_VAR_docker_runner_token=<your-token>
export TF_VAR_dind_runner_token=<your-token>
export TF_VAR_rocky8_runner_token=<your-token>
export TF_VAR_rocky9_runner_token=<your-token>
export TF_VAR_nix_runner_token=<your-token>

# Initialize and deploy
just init
just plan
just apply
```

### Check Status

```bash
# All runners
just status

# Specific runner
just docker-status
just dind-status
just nix-status

# View logs
just logs bates-docker
```

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues and solutions.

### Quick Checks

```bash
# Check if runners are registered
kubectl get pods -n bates-ils-runners

# Check HPA status
kubectl get hpa -n bates-ils-runners

# View runner logs
kubectl logs -n bates-ils-runners -l release=bates-docker

# Check events
kubectl get events -n bates-ils-runners --sort-by='.lastTimestamp'
```

## Related Documentation

- [Runner Selection Guide](runner-selection.md)
- [Docker/DinD Builds](docker-builds.md)
- [Nix/Attic Integration](nix-builds.md)
- [HPA Tuning](hpa-tuning.md)
- [Troubleshooting](troubleshooting.md)
