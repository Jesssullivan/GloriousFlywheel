---
title: Clusters and Environments
order: 20
---

# Clusters and Environments

This document describes the Kubernetes clusters, their roles, namespace layout, authentication methods, and database considerations.

## Cluster Roles

| Cluster | Role | Status | Access |
|---------|------|--------|--------|
| **beehive** | Development | Active | On-campus or via SOCKS proxy |
| **rigel** | Staging / Production | Planned | TBD |

### beehive

The development cluster, managed by Rancher (UI at `rancher2.bates.edu`). All initial development, testing, and iteration happens here. The cluster runs on campus infrastructure and requires a SOCKS proxy for off-campus access. See [Proxy and Access](./proxy-and-access.md) for connectivity details.

### rigel

Reserved for staging and production workloads. Not yet provisioned. When brought online, it will mirror the beehive namespace layout but with production-grade resource limits, replica counts, and ingress configuration.

## Namespace Layout

Each functional component runs in its own namespace to provide resource isolation and RBAC boundaries.

```mermaid
graph TD
    subgraph beehive["Beehive Cluster"]
        NS1[attic-cache-dev]
        NS2[bates-ils-runners]
        NS3[runner-dashboard]
    end
    NS1 -->|"PostgreSQL via CNPG"| DB[(CloudNativePG)]
    NS2 -->|"env: ATTIC_SERVER"| NS1
```

### attic-cache-dev

Houses the Attic binary cache server and its PostgreSQL database:

- **atticd** -- the cache daemon, running in monolithic mode (`--mode monolithic`) so it auto-runs database migrations on startup
- **CloudNativePG cluster** -- manages the PostgreSQL instance(s) for Attic's metadata store
- **PVCs** -- Longhorn-backed persistent volumes for cache object storage

### bates-ils-runners

Contains all GitLab Runner deployments. Each runner type (docker, dind, rocky8, rocky9, nix) runs as a separate pod managed by a Helm release. Runners reference the Attic cache via the `ATTIC_SERVER` environment variable pointing into the `attic-cache-dev` namespace.

### runner-dashboard

Hosts the SvelteKit runner dashboard application. The dashboard reads runner status from the GitLab API and displays build metrics.

## Kubernetes Authentication

Authentication differs between local development and CI pipelines.

### Local Development

Use a kubeconfig file obtained from Rancher:

1. Log into Rancher at `rancher2.bates.edu` (requires SOCKS proxy if off-campus).
2. Download the kubeconfig for the target cluster.
3. Save it as `kubeconfig-beehive` at the overlay repository root (this path is gitignored).
4. Pass it to OpenTofu:

```bash
tofu plan \
  -var k8s_config_path=$PWD/kubeconfig-beehive \
  -var cluster_context=beehive \
  ...
```

### CI Pipelines

CI uses the GitLab Kubernetes Agent, which provides in-cluster authentication without a kubeconfig file or proxy. The agent path follows the pattern:

```
bates-ils/projects/kubernetes/gitlab-agents:{environment}
```

This is set in the tfvars files used by CI and requires no additional network configuration.

## CloudNativePG (PostgreSQL)

The Attic cache stores metadata in PostgreSQL, managed by the CloudNativePG operator.

### Key Details

- Operator must be installed cluster-wide before deploying the Attic stack.
- The OpenTofu modules create a `Cluster` custom resource that provisions PostgreSQL instances within the `attic-cache-dev` namespace.
- Instance count and storage size are configured in `organization.yaml` under `environments.<env>.cache.postgres`.

### Connection String Encoding

CloudNativePG generates random passwords for database users. These passwords are stored in Kubernetes secrets and injected into the Attic pod as environment variables.

**Passwords must be URL-encoded in connection strings.** If the generated password contains characters like `#`, `:`, `?`, `@`, `<`, `>`, or `&`, an unencoded connection string will fail to parse. The OpenTofu modules handle this encoding automatically via the `urlencode()` function, but be aware of this requirement if constructing connection strings manually.

```
# Correct
postgresql://attic:p%40ss%3Aword@cnpg-cluster-rw:5432/attic

# Incorrect -- will fail
postgresql://attic:p@ss:word@cnpg-cluster-rw:5432/attic
```

## Related Documentation

- [Quick Start](./quick-start.md) -- deployment walkthrough
- [Customization Guide](./customization-guide.md) -- organization.yaml reference
- [Proxy and Access](./proxy-and-access.md) -- SOCKS proxy setup for off-campus access
