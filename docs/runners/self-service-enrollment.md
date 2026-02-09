# Self-Service Runner Enrollment

Guide for organization project owners to use the shared HPA runner pool.

## Quick Start

Runners are registered at the **organization group level**. Any project in the group
can use them immediately by specifying the correct tags in `.gitlab-ci.yml`:

```yaml
build:
  tags: [docker, linux, amd64]
  script:
    - make build
```

No registration tokens, no admin requests. Add tags and go.

## Runner Types

| Type   | Tags                           | Use Case                                 |
| ------ | ------------------------------ | ---------------------------------------- |
| docker | `docker`, `linux`, `amd64`     | General CI: linting, testing, builds     |
| dind   | `docker`, `dind`, `privileged` | Docker-in-Docker: container image builds |
| rocky8 | `rocky8`, `rhel8`, `linux`     | RHEL 8 compatibility testing             |
| rocky9 | `rocky9`, `rhel9`, `linux`     | RHEL 9 compatibility testing             |
| nix    | `nix`, `flakes`                | Nix builds with Attic binary cache       |

**Choosing a runner:**

- Default to `docker` for most workloads.
- Use `dind` only when you need to build container images (`docker build`).
- Use `rocky8`/`rocky9` when your target is RHEL and you need OS-level packages.
- Use `nix` for Nix flake builds; the Attic cache is pre-configured.

## CI/CD Components

The `attic-cache` project publishes reusable CI/CD components. Use `include: component:`
syntax instead of writing jobs from scratch.

### Available Components

| Component      | Description                           |
| -------------- | ------------------------------------- |
| `docker-job`   | Standard Docker runner job            |
| `dind-job`     | Docker-in-Docker job                  |
| `rocky8-job`   | Rocky 8 runner job                    |
| `rocky9-job`   | Rocky 9 runner job                    |
| `nix-job`      | Nix runner job with Attic cache       |
| `docker-build` | Build and push container images       |
| `k8s-deploy`   | Deploy to Kubernetes via GitLab Agent |

### Usage

```yaml
include:
  - component: $CI_SERVER_FQDN/{org}/projects/iac/attic-cache/docker-job@main
    inputs:
      stage: build
      script: make build

  - component: $CI_SERVER_FQDN/{org}/projects/iac/attic-cache/nix-job@main
    inputs:
      stage: build
      script: nix build .#default
```

Pin to a tag or branch as needed. `@main` tracks the latest stable version.

### Overriding Defaults

Components accept `inputs:` for customization. Common inputs:

```yaml
include:
  - component: $CI_SERVER_FQDN/{org}/projects/iac/attic-cache/docker-job@main
    inputs:
      stage: test
      script: make test
      image: node:20-alpine
      timeout: 30m
```

## Kubernetes Deployment

K8s deployments use GitLab Agent `ci_access`. Two clusters are available:

| Cluster      | Environment  | Agent Path                                                |
| ------------ | ------------ | --------------------------------------------------------- |
| dev-cluster  | dev          | `{org}/projects/kubernetes/gitlab-agents:dev-cluster`     |
| prod-cluster | staging/prod | `{org}/projects/kubernetes/gitlab-agents:prod-cluster`    |

### Using k8s-deploy

```yaml
include:
  - component: $CI_SERVER_FQDN/{org}/projects/iac/attic-cache/k8s-deploy@main
    inputs:
      stage: deploy
      environment: dev
      cluster: dev-cluster
      manifests: deploy/k8s/
```

The component sets `KUBECONFIG` automatically via the agent. No manual kubeconfig
files or service account tokens required.

### Direct Agent Access

If you need more control than the component provides:

```yaml
deploy:
  tags: [docker, linux, amd64]
  image:
    name: bitnami/kubectl:latest
    entrypoint: [""]
  script:
    - kubectl config use-context {org}/projects/kubernetes/gitlab-agents:dev-cluster
    - kubectl apply -f deploy/k8s/
```

## Cache Integration

### Bazel Remote Cache

Docker and Nix runners inject `BAZEL_REMOTE_CACHE` automatically. Add to your
`.bazelrc`:

```
build:runner-pool --remote_cache=${BAZEL_REMOTE_CACHE}
```

Then build with `bazel build --config=runner-pool //...`. See
[cache-integration.md](cache-integration.md) for details.

### Attic Nix Binary Cache

Nix runners are pre-configured with the Attic binary cache at
`attic.dev-cluster.example.com`. Nix builds automatically push and pull from the
shared cache. See [cache-integration.md](cache-integration.md) for downstream
project setup.

## Namespace Isolation

Each job runs in an ephemeral `ci-job-*` Kubernetes namespace with:

- **NetworkPolicy**: default-deny ingress, full egress
- **ResourceQuota**: 16 CPU, 32Gi memory, 50 pods
- **LimitRange**: sensible container defaults
- **RBAC**: read-only access to pods, deployments, HPAs, jobs, events

This applies to `docker`, `rocky8`, `rocky9`, and `nix` runners. The `dind`
runner is the exception -- it uses a shared namespace with privileged access.
See [security-model.md](security-model.md) for full details.

## Tag Strategy: Why No `kubernetes` Tag

Self-hosted runners intentionally **exclude** the `kubernetes` tag from their
registrations. Overlay CI pipelines use `default: tags: [kubernetes]` to target
GitLab SaaS shared runners for jobs that need internet access (e.g., cloning
the upstream repo from GitHub, downloading kubectl).

Including `kubernetes` on self-hosted runners causes them to grab overlay CI
jobs. On restricted networks (e.g., institutional clusters that can reach
gitlab.com but not github.com), this causes failures when jobs try to clone
from GitHub.

**Rule of thumb:** self-hosted runners should only be tagged with their
workload type (`docker`, `nix`, `rocky8`, etc). Projects request specific
runners by matching these workload tags. Generic infrastructure jobs stay on
SaaS shared runners.

This was discovered during the first non-dogfooding deployment of
flywheel-derived runners, where the Bates beehive cluster runners were
unexpectedly picking up overlay pipeline jobs.

## See Also

- [Project Onboarding Guide](project-onboarding.md) -- step-by-step enrollment for new projects
- [Resource Limits Reference](resource-limits.md) -- job pod resource limits and workload profiles
