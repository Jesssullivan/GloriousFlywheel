---
title: Configuration Reference
order: 10
---

# Configuration Reference

The `organization.yaml` file is the central configuration source for an
attic-iac deployment. It defines the organization identity, target environments,
runner fleet, and cache settings.

## Schema

### Top-Level Structure

```yaml
organization:
  name: <string>
  environments:
    <env_name>: <environment_config>

runners:
  <runner_name>: <runner_config>

cache:
  server: <string>
  name: <string>
  storage_size: <string>
```

### organization

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Organization display name |
| `environments` | map | Map of environment name to environment configuration |

### organization.environments.\<env_name\>

Each key under `environments` names a deployment target (e.g., `beehive`,
`tinyland`).

| Field | Type | Description |
|-------|------|-------------|
| `cluster_context` | string | Kubernetes context name or GitLab Agent path |
| `namespace` | string | Target Kubernetes namespace for this environment |
| `domain` | string | Base domain for ingress hosts in this environment |

Example:

```yaml
organization:
  name: bates-ils
  environments:
    beehive:
      cluster_context: beehive
      namespace: attic-cache
      domain: apps.bates.edu
```

### runners

A map of runner names to their configuration. Each runner corresponds to a
GitLab Runner deployment in the target cluster.

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Runner executor type: `docker`, `dind`, `rocky8`, `rocky9`, `nix` |
| `image` | string | Default container image for job execution |
| `concurrent_jobs` | integer | Maximum number of concurrent jobs |
| `tags` | list of string | GitLab CI tags that route jobs to this runner |
| `resources` | object | Kubernetes resource requests and limits |
| `hpa` | object | Horizontal Pod Autoscaler configuration |

#### runners.\<name\>.resources

| Field | Type | Description |
|-------|------|-------------|
| `cpu_request` | string | CPU request (e.g., `"500m"`) |
| `cpu_limit` | string | CPU limit (e.g., `"2"`) |
| `memory_request` | string | Memory request (e.g., `"1Gi"`) |
| `memory_limit` | string | Memory limit (e.g., `"4Gi"`) |

Note: resource fields must be flat keys in TOML-based runner configuration.
Nested tables cause type mismatches in GitLab Runner 17.x.

#### runners.\<name\>.hpa

| Field | Type | Description |
|-------|------|-------------|
| `min_replicas` | integer | Minimum pod count |
| `max_replicas` | integer | Maximum pod count |
| `target_cpu_utilization` | integer | CPU utilization percentage target for scaling |

Example:

```yaml
runners:
  docker:
    type: docker
    image: docker:27
    concurrent_jobs: 4
    tags:
      - docker
      - linux
    resources:
      cpu_request: "500m"
      cpu_limit: "2"
      memory_request: "1Gi"
      memory_limit: "4Gi"
    hpa:
      min_replicas: 1
      max_replicas: 3
      target_cpu_utilization: 70
```

### cache

Configuration for the Attic binary cache server.

| Field | Type | Description |
|-------|------|-------------|
| `server` | string | Full URL of the Attic cache server |
| `name` | string | Cache name within the Attic server |
| `storage_size` | string | Persistent volume size for cache storage (e.g., `"50Gi"`) |

Example:

```yaml
cache:
  server: https://attic.apps.bates.edu
  name: bates
  storage_size: 50Gi
```

## Validation

The pipeline validate stage checks `organization.yaml` against this schema. The
validation confirms:

- All required fields are present
- Environment names are valid DNS labels
- Runner types are from the allowed set
- Resource values parse as valid Kubernetes quantities
- Cross-references between runners and environments are consistent

## Related

- [OpenTofu Modules](./tofu-modules.md) -- modules that consume this configuration
- [Environment Variables](./environment-variables.md) -- variables that supplement config
- [Pipeline Overview](../ci-cd/pipeline-overview.md) -- validation stage details
