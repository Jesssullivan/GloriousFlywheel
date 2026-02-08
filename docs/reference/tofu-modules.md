---
title: OpenTofu Modules
order: 1
---

# OpenTofu Modules

All reusable infrastructure modules live in `tofu/modules/`. Each module is
designed to be composed by stack root configurations in `tofu/stacks/`.

## attic-server

Deploys the Attic binary cache server as a Kubernetes Deployment with an
associated Service and Ingress.

- **Inputs**: image, replicas, storage size, database URL, server URL, cache name,
  namespace, ingress host, TLS secret name
- **Outputs**: service endpoint, ingress host
- **Dependencies**: `cloudnative-pg` (for PostgreSQL), `k8s-namespace`

## attic-gc

Deploys a garbage collection CronJob that periodically cleans expired entries
from the Attic cache.

- **Inputs**: image, schedule (cron expression), cache name, server URL, namespace
- **Outputs**: cronjob name
- **Dependencies**: `attic-server`

## cloudnative-pg

Provisions a PostgreSQL cluster using the CloudNativePG operator.

- **Inputs**: cluster name, instances, storage size, database name, namespace,
  backup schedule
- **Outputs**: connection URI (with urlencode-safe credentials), cluster name
- **Dependencies**: CloudNativePG operator must be installed in the cluster

Note: connection strings must use `urlencode()` for passwords, as CNPG may
generate credentials containing URL-unsafe characters.

## gitlab-runner

Deploys a GitLab Runner with Horizontal Pod Autoscaler support. Supports
multiple runner types (docker, dind, rocky8, rocky9, nix) through configuration
variables.

- **Inputs**: runner name, type, image, tags, concurrent jobs, namespace,
  registration token, resource requests/limits, HPA min/max replicas,
  CPU utilization target
- **Outputs**: runner name, HPA name
- **Dependencies**: `k8s-namespace`, GitLab group/project for registration

## k8s-namespace

Creates a Kubernetes namespace with RBAC bindings and optional resource quotas.

- **Inputs**: namespace name, labels, annotations, resource quota (cpu, memory,
  pods), role bindings
- **Outputs**: namespace name
- **Dependencies**: none

## k8s-ingress

Creates a Kubernetes Ingress resource with TLS termination via cert-manager.

- **Inputs**: name, namespace, host, service name, service port, TLS secret name,
  cert-manager cluster issuer, annotations
- **Outputs**: ingress name, host
- **Dependencies**: cert-manager operator, target Service

## k8s-deployment

A generic Kubernetes Deployment module for workloads that do not need
specialized logic.

- **Inputs**: name, namespace, image, replicas, ports, environment variables,
  resource requests/limits, volume mounts, liveness/readiness probes
- **Outputs**: deployment name, selector labels
- **Dependencies**: `k8s-namespace`

## k8s-service

Creates a Kubernetes Service to expose a Deployment.

- **Inputs**: name, namespace, selector labels, port, target port, type
  (ClusterIP, NodePort, LoadBalancer)
- **Outputs**: service name, cluster IP
- **Dependencies**: target Deployment

## k8s-secret

Creates a Kubernetes Secret from a map of key-value pairs.

- **Inputs**: name, namespace, data (map of string to string), type (Opaque,
  kubernetes.io/tls, etc.)
- **Outputs**: secret name
- **Dependencies**: `k8s-namespace`

## runner-dashboard

Deploys the SvelteKit runner-dashboard application as a Kubernetes Deployment
with Service and Ingress.

- **Inputs**: image, replicas, namespace, ingress host, TLS secret name,
  GitLab API URL, OAuth client ID, OAuth client secret, environment variables
- **Outputs**: service endpoint, ingress host
- **Dependencies**: `k8s-namespace`, `k8s-ingress`

## monitoring

Creates a Prometheus ServiceMonitor resource for scraping metrics from a target
Service.

- **Inputs**: name, namespace, service name, port name, path, interval,
  labels (for Prometheus selector matching)
- **Outputs**: servicemonitor name
- **Dependencies**: Prometheus Operator (kube-prometheus-stack or equivalent)

## Related

- [Configuration Reference](./config-reference.md) -- organization.yaml schema
- [Pipeline Overview](../ci-cd/pipeline-overview.md) -- how modules are validated and deployed
- [Environment Variables](./environment-variables.md) -- variables consumed by stacks
