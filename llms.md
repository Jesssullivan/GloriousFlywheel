# Attic IaC Documentation

## Overview

This repository provides a complete Infrastructure as Code (IaC) solution for deploying an Attic Nix binary cache on Kubernetes. Attic is a self-hosted binary cache for Nix that stores build artifacts (NARs) to accelerate Nix builds across teams and CI/CD pipelines.

**Key Features:**

- Production-grade Kubernetes deployment with Horizontal Pod Autoscaler (HPA)
- PostgreSQL high-availability cluster using CloudNativePG
- S3-compatible object storage for NAR files
- Comprehensive security hardening (Pod Security Standards, NetworkPolicies, TLS)
- Complete observability stack (Prometheus, Grafana, Loki)
- GitLab CI/CD pipelines with automated deployment gates
- Modular OpenTofu architecture for reusability

**Benefits:**

- **Faster builds**: Skip rebuilding unchanged packages
- **Consistent artifacts**: Share exact build outputs across environments
- **Reduced CI time**: CI jobs pull from cache instead of rebuilding
- **Bandwidth savings**: Share builds within your organization

## Architecture

### System Architecture Diagram

```
                                    Internet
                                        |
                                        v
                            +-------------------+
                            |   Load Balancer   |
                            |   DNS / TLS       |
                            +-------------------+
                                        |
                                        v
                            +-------------------+
                            |     Traefik       |
                            |  Ingress + TLS    |
                            +-------------------+
                                        |
                                        v
+---------------------------------------------------------------------------------+
|                              nix-cache Namespace                                |
|                                                                                 |
|  +------------------+     +------------------+     +------------------+          |
|  |   Attic API      |     |   Attic API      |     |   Attic API      |          |
|  |   (replica 1)    |     |   (replica 2)    |     |   (replica N)    |          |
|  +------------------+     +------------------+     +------------------+          |
|           |                        |                        |                   |
|           +------------------------+------------------------+                   |
|                                    |                                            |
|                        +-----------v-----------+                                |
|                        |    K8s Service        |                                |
|                        |    (ClusterIP)        |                                |
|                        +-----------------------+                                |
|                                                                                 |
|  +------------------+     +-----------------------+                             |
|  |   Attic GC       |     |   HorizontalPod       |                             |
|  |   (1 replica)    |     |   Autoscaler          |                             |
|  +------------------+     |   (2-10 replicas)     |                             |
|                           +-----------------------+                             |
|                                                                                 |
|  +-------------------------------------------------------------------------+   |
|  |                     CloudNativePG PostgreSQL Cluster                    |   |
|  |  +-------------+     +-------------+     +-------------+                |   |
|  |  |  Primary    |<--->|  Replica 1  |<--->|  Replica 2  |                |   |
|  |  |  (RW)       |     |  (RO)       |     |  (RO)       |                |   |
|  |  +-------------+     +-------------+     +-------------+                |   |
|  |        |                                                                |   |
|  |        v                                                                |   |
|  |  +-------------------+  +-------------------+  +-------------------+    |   |
|  |  | attic-pg-rw       |  | attic-pg-ro       |  | attic-pg-r        |    |   |
|  |  | (Primary Service) |  | (Replica Service) |  | (Any Service)     |    |   |
|  |  +-------------------+  +-------------------+  +-------------------+    |   |
|  +-------------------------------------------------------------------------+   |
+---------------------------------------------------------------------------------+
           |                                |                    |
           v                                v                    v
+------------------+             +-------------------+    +------------------+
|  S3 Object       |             |  S3 Object        |    |   CNPG Operator  |
|  Storage         |             |  Storage          |    |   (cnpg-system)  |
|  500GB+ NARs     |             |  PG Backups       |    +------------------+
+------------------+             +-------------------+
```

### Components

#### 1. Attic API Server (HPA-enabled)

- **Replicas**: 2-10 (managed by HPA)
- **Scaling Metrics**:
  - CPU utilization: 70% target
  - Memory utilization: 80% target
- **Health Check**: `/nix-cache-info`
- **Resources**:
  - Request: 100m CPU, 128Mi memory
  - Limit: 1000m CPU, 512Mi memory

#### 2. Attic Garbage Collector

- **Replicas**: 1 (fixed)
- **Purpose**: Background LRU garbage collection
- **Interval**: Every 12 hours
- **Retention**: 3 months default

#### 3. S3 Object Storage

- **Capacity**: 500GB blocks
- **Features**:
  - S3-compatible API
  - Content-addressed chunking
  - Versioning enabled for data protection

#### 4. CloudNativePG PostgreSQL (Production-Grade)

Production-grade PostgreSQL cluster using the CloudNativePG operator.

- **Instances**: 3 (1 primary + 2 replicas) for HA
- **Services**:
  - `attic-pg-rw`: Read-write (primary only)
  - `attic-pg-ro`: Read-only (replicas)
  - `attic-pg-r`: Any instance (round-robin)
- **Storage**: 10Gi per instance on persistent volumes
- **Resources**: 512Mi-1Gi RAM, 250m-1000m CPU

**Security Features:**

| Feature           | Implementation                              |
| ----------------- | ------------------------------------------- |
| TLS Encryption    | All connections use SSL/TLS                 |
| Authentication    | SCRAM-SHA-256 only (no MD5)                 |
| pg_hba.conf       | `hostssl all all all scram-sha-256`         |
| Audit Logging     | DDL statements, connections, disconnections |
| Statement Timeout | 60s default (prevents runaway queries)      |
| Network Policies  | Only Attic pods and CNPG operator allowed   |

**Backup & Recovery:**

| Feature         | Configuration                    |
| --------------- | -------------------------------- |
| WAL Archiving   | Continuous to S3                 |
| Full Backups    | Daily at midnight UTC            |
| Retention       | 30 days                          |
| PITR            | Point-in-time recovery supported |
| Backup Location | `s3://attic-pg-backup/attic-pg/` |

## Infrastructure Modules

### hpa-deployment Module

Generic HPA-enabled deployment module located at `tofu/modules/hpa-deployment/`.

```hcl
module "service" {
  source = "../../modules/hpa-deployment"

  name           = "my-service"
  namespace      = "my-namespace"
  image          = "my-image:tag"
  container_port = 8080

  # HPA configuration
  min_replicas          = 2
  max_replicas          = 10
  cpu_target_percent    = 70
  memory_target_percent = 80

  # Ingress
  enable_ingress = true
  ingress_host   = "my-service.example.com"
}
```

**Supported Features:**

- Horizontal Pod Autoscaler (HPA v2)
- Pod Disruption Budget (PDB)
- Ingress with TLS (cert-manager)
- Prometheus metrics annotations
- Topology spread constraints
- ConfigMap/Secret volume mounts

### civo-object-store Module

S3-compatible object storage provisioning at `tofu/modules/civo-object-store/`.

```hcl
module "storage" {
  source = "../../modules/civo-object-store"

  name        = "my-cache"
  region      = "NYC1"
  max_size_gb = 500
}
```

### cnpg-operator Module

CloudNativePG operator installation at `tofu/modules/cnpg-operator/`.

```hcl
module "cnpg" {
  source = "../../modules/cnpg-operator"

  namespace        = "cnpg-system"
  create_namespace = true
  chart_version    = "0.20.0"

  enable_pod_monitor = true
}
```

### postgresql-cnpg Module

Production PostgreSQL cluster at `tofu/modules/postgresql-cnpg/`.

```hcl
module "pg" {
  source = "../../modules/postgresql-cnpg"

  name          = "my-pg"
  namespace     = "my-namespace"
  database_name = "mydb"
  owner_name    = "myapp"

  # HA Configuration
  instances = 3

  # Storage
  storage_size  = "10Gi"
  storage_class = "standard"

  # Backup
  enable_backup       = true
  backup_s3_endpoint  = "https://s3.example.com"
  backup_s3_bucket    = "my-pg-backup"

  # Network isolation
  enable_network_policy = true
  allowed_pod_labels = {
    "app.kubernetes.io/name" = "myapp"
  }
}
```

**Security Features:**

- TLS encryption (hostssl only)
- SCRAM-SHA-256 authentication
- Network policies (optional)
- Audit logging
- Statement timeout protection

**Outputs:**

- `database_url`: Full connection string (sensitive)
- `host_rw`: Read-write hostname
- `host_ro`: Read-only hostname
- `credentials_secret_name`: K8s secret with credentials

### attic-tokens Module

JWT token management for Attic authentication at `tofu/modules/attic-tokens/`.

```hcl
module "tokens" {
  source = "../../modules/attic-tokens"

  namespace = "nix-cache"

  ci_tokens = {
    "gitlab-myrepo" = {
      cache    = "main"
      push     = true
      pull     = true
      validity = "90d"
    }
  }

  root_token_validity = "180d"
}
```

## Deployment

### GitLab CI Pipeline Flow

#### Deployment Strategy

| Branch/Tag                              | Staging     | Production  | Notes                                   |
| --------------------------------------- | ----------- | ----------- | --------------------------------------- |
| Feature branches (`feature/*`, `fix/*`) | Plan only   | -           | No apply, review plan artifacts         |
| `main` branch                           | Auto-deploy | Manual      | Staging auto-deploys after tests pass   |
| Semver tags (`v*.*.*`)                  | -           | Auto-deploy | Production auto-deploys on release tags |

#### Pipeline Diagram

```
                                 Feature Branch
                                      |
                                      v
+--------+   +--------+   +----------+   +---------------+
| tofu   |-->| tofu   |-->| SAST     |-->| Plan Only     |
|validate|   | plan   |   | Secret   |   | (no apply)    |
+--------+   +--------+   | Detection|   +---------------+
                          +----------+

                                 Main Branch
                                      |
                                      v
+--------+   +--------+   +----------+   +-----------+   +----------+
| tofu   |-->| tofu   |-->| SAST     |-->| tofu      |-->| HPA      |
|validate|   | plan   |   | Secret   |   | apply     |   | validate |
+--------+   +--------+   | Detection|   | (staging) |   +----------+
                          +----------+   +-----------+         |
                                               |               v
                                               |         +----------+
                                               |         | health   |
                                               |         | check    |
                                               |         +----------+
                                               v               |
                                         +-----------+         v
                                         | tofu      |   +----------+
                                         | apply     |   | resources|
                                         |(prod)     |   | report   |
                                         | [manual]  |   +----------+
                                         +-----------+

                              Semver Tag (v*.*.*)
                                      |
                                      v
+--------+   +--------+   +----------+   +-----------+   +----------+
| tofu   |-->| tofu   |-->| SAST     |-->| tofu      |-->| HPA      |
|validate|   | plan   |   | Secret   |   | apply     |   | validate |
+--------+   +--------+   | Detection|   |(production)|  +----------+
                          +----------+   | [auto]    |         |
                                         +-----------+         v
                                                         +----------+
                                                         | health   |
                                                         | check    |
                                                         +----------+
                                                               |
                                                               v
                                                         +----------+
                                                         | resources|
                                                         | report   |
                                                         +----------+
```

#### Deployment Gates

| Gate               | Staging      | Production                           |
| ------------------ | ------------ | ------------------------------------ |
| Tests pass         | Required     | Required                             |
| Plan validation    | Required     | Required                             |
| Health check       | Post-deploy  | Post-deploy                          |
| Manual approval    | Not required | Required (via protected environment) |
| Rollback available | Yes          | Yes                                  |

### HPA Scaling Strategy

#### Default Behavior

| Direction  | Stabilization  | Max Change     | Period |
| ---------- | -------------- | -------------- | ------ |
| Scale Up   | 0s (immediate) | 100% or 4 pods | 15s    |
| Scale Down | 300s (5 min)   | 10% or 2 pods  | 60s    |

#### Service-Specific Tuning

| Service    | CPU Target | Memory Target | Min | Max | Notes               |
| ---------- | ---------- | ------------- | --- | --- | ------------------- |
| Attic      | 70%        | 80%           | 2   | 10  | Cache miss storms   |
| Quay       | 60%        | 70%           | 2   | 8   | Long image pulls    |
| Pulp       | 70%        | 75%           | 2   | 6   | Moderate traffic    |
| DNF Mirror | 80%        | 85%           | 2   | 12  | Burst sync patterns |

### Rollback Procedures

#### Quick Rollback (kubectl)

```bash
kubectl rollout undo deployment/attic -n nix-cache
```

#### Image Rollback (CI job)

1. Go to CI/CD > Pipelines
2. Run `tofu:rollback` job
3. Set `ROLLBACK_IMAGE` variable to target image

#### Full Infrastructure Rollback

1. Find previous successful pipeline
2. Re-run `tofu:apply:production` job from that pipeline

### Deployment Freeze

To block all deployments (maintenance, incidents):

1. Set CI/CD variable: `DEPLOYMENT_FREEZE=true`
2. Optional: Set `FREEZE_REASON` and `FREEZE_CONTACT`
3. All apply jobs will fail with freeze message

## Security

### Security Considerations

#### PostgreSQL Security (CloudNativePG)

| Control               | Implementation                             |
| --------------------- | ------------------------------------------ |
| Encryption in Transit | TLS required (`hostssl` in pg_hba.conf)    |
| Password Storage      | SCRAM-SHA-256 (no MD5)                     |
| Connection Limits     | `max_connections = 100`                    |
| Query Protection      | `statement_timeout = 60s`                  |
| Audit Trail           | `log_statement = ddl`, connections logged  |
| Network Isolation     | NetworkPolicy restricts to Attic pods only |
| Credentials           | K8s Secret, auto-rotated by CNPG           |

#### Secrets Management

- JWT signing keys stored in K8s Secrets
- Database credentials auto-generated by CNPG
- S3 credentials via cloud provider API
- All secrets marked `sensitive = true` in OpenTofu

#### Network Policies

- Default deny ingress for namespace
- PostgreSQL: Only Attic pods and CNPG operator
- Attic API: Only Traefik ingress
- Egress: DNS, PostgreSQL, S3 (HTTPS)

#### Authentication

- Attic uses RS256 JWT tokens
- CI tokens have restricted push/pull permissions
- Root token for admin operations only
- No superuser access from application

#### Token Management

**Token Types:**

| Type           | Permissions     | Use Case                            |
| -------------- | --------------- | ----------------------------------- |
| **Read-only**  | Pull from cache | Local development, read-only CI     |
| **Read-write** | Pull + push     | CI builds that contribute artifacts |
| **Admin**      | Full access     | Cache management, token rotation    |

**Token Rotation Schedule:**

| Token Type       | Validity Period | Rotation Trigger      | Automation                |
| ---------------- | --------------- | --------------------- | ------------------------- |
| CI Tokens        | 90 days         | 14 days before expiry | GitLab scheduled pipeline |
| Service Tokens   | 365 days        | 30 days before expiry | GitLab scheduled pipeline |
| Root Token       | 180 days        | 30 days before expiry | Manual with notification  |
| Read-Only Tokens | 90 days         | 14 days before expiry | GitLab scheduled pipeline |

### Security Hardening Checklist

#### TLS/Encryption

- [x] **Ingress TLS** - Let's Encrypt certificates via cert-manager
- [x] **PostgreSQL TLS** - CloudNativePG automatic TLS
- [x] **S3 TLS** - HTTPS endpoints enforced
- [x] **PostgreSQL Encryption at Rest** - Encrypted storage volumes
- [x] **S3 Server-Side Encryption** - AES-256 enabled
- [x] **Kubernetes Secrets** - etcd encryption

#### Network Security

- [x] **PostgreSQL Network Policy** - Restrict database access to Attic pods and CNPG operator
- [x] **Attic API Network Policy** - Restrict API access to Traefik ingress
- [x] **Default Deny Policy** - Block all unspecified traffic in namespace
- [x] **Rate Limiting** - Traefik middleware for API protection

#### RBAC & Access Control

- [x] **Service Accounts** - Dedicated SA per component
- [x] **Minimal Permissions** - Principle of least privilege
- [x] **Pod Security Standards** - Enforce baseline/restricted
- [x] **Token Scopes** - Minimal permissions per token
- [x] **Token Expiration** - All tokens have expiry
- [x] **Token Revocation** - Revocation list maintained

#### Container Security

- [x] **Pinned Image Tags** - Use specific versions (commit hashes)
- [x] **Non-Root User** - Run as non-root (UID 1000)
- [x] **Read-Only Root Filesystem** - With emptyDir for /tmp
- [x] **No Privilege Escalation** - Disabled via security context
- [x] **Drop Capabilities** - All capabilities dropped

#### Audit Logging

- [x] **API Server Audit** - Kubernetes audit logging enabled
- [x] **Log Retention** - 90 days for security logs
- [ ] **Centralized Logging** - Ship logs to Loki/ELK (recommended)

#### Secret Management

- [x] **No Secrets in Git** - .gitignore configured
- [x] **Secrets as K8s Secrets** - Not ConfigMaps
- [x] **Automated Rotation** - Time-based rotation
- [x] **Rotation Tracking** - Kubernetes annotations

#### CI/CD Security

- [x] **SAST Scanning** - GitLab SAST enabled
- [x] **Secret Detection** - GitLab secret detection
- [x] **Protected Variables** - Masked CI/CD variables

### Backup Policy

#### Backup Architecture

The Attic deployment has three critical data stores that require backup:

1. **PostgreSQL Database** - Metadata, cache manifests, chunk references
2. **S3 Object Storage** - NAR files and chunks (the actual cached data)
3. **Kubernetes Secrets** - Authentication tokens, JWT signing keys

#### PostgreSQL Backups (CloudNativePG)

| Type          | Schedule        | Retention | Storage              |
| ------------- | --------------- | --------- | -------------------- |
| Full Backup   | Daily 00:00 UTC | 30 days   | S3 (attic-pg-backup) |
| WAL Archives  | Continuous      | 30 days   | S3 (attic-pg-backup) |
| Point-in-Time | On-demand       | N/A       | Restored to cluster  |

**Recovery Procedures:**

Point-in-Time Recovery (PITR):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: attic-pg-recovery
  namespace: nix-cache
spec:
  instances: 1
  storage:
    size: 10Gi
  bootstrap:
    recovery:
      source: attic-pg
      recoveryTarget:
        targetTime: "2024-01-15T10:30:00Z"
```

#### S3 Object Storage (NAR Files)

- **Versioning**: Enabled for data protection
- **Lifecycle Rules**: 90-day retention for old versions
- **Transition to IA**: After 30 days of inactivity

#### Retention Policy Summary

| Data Type       | Backup Frequency | Retention Period   | Storage Location       |
| --------------- | ---------------- | ------------------ | ---------------------- |
| PostgreSQL Full | Daily            | 30 days            | S3 (attic-pg-backup)   |
| PostgreSQL WAL  | Continuous       | 30 days            | S3 (attic-pg-backup)   |
| S3 NAR Objects  | Versioned        | 90 days (versions) | S3 (nix-cache)         |
| K8s Secrets     | On change        | Indefinite         | Sealed Secrets / Vault |
| Audit Logs      | Continuous       | 90 days            | Loki / S3              |

#### Disaster Recovery Scenarios

**Scenario 1: Database Corruption**

1. Stop Attic API and GC deployments
2. Perform PITR to last known good state
3. Verify data integrity
4. Resume Attic deployments

RTO: 30 minutes | RPO: Seconds (WAL archiving)

**Scenario 2: Complete Cluster Loss**

1. Provision new Kubernetes cluster
2. Deploy CNPG operator
3. Restore PostgreSQL from S3 backup
4. Restore secrets from sealed secrets
5. Deploy Attic stack
6. Verify S3 connectivity

RTO: 2 hours | RPO: 24 hours (daily backup)

**Scenario 3: S3 Data Loss**

1. Identify affected objects
2. Restore from S3 versioning
3. Run Attic integrity check
4. Re-push affected packages if necessary

RTO: Variable | RPO: Depends on versioning

## Operations

### Health Check Endpoints

#### `/nix-cache-info` - Cache Info (Public)

**Purpose**: Returns Nix binary cache metadata. Used as the primary health check endpoint.

**Response** (200 OK):

```
StoreDir: /nix/store
WantMassQuery: 1
Priority: 40
```

**Usage**: Kubernetes liveness/readiness probes, external monitoring, Nix client verification

**Configuration**:

```yaml
livenessProbe:
  httpGet:
    path: /nix-cache-info
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /nix-cache-info
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

#### `/metrics` - Prometheus Metrics

**Purpose**: Exposes Prometheus-formatted metrics for observability.

**Key Metrics**:

| Metric                          | Type      | Description           | Alert Threshold |
| ------------------------------- | --------- | --------------------- | --------------- |
| `http_requests_total`           | Counter   | Total HTTP requests   | N/A (rate)      |
| `http_request_duration_seconds` | Histogram | Request latency       | p99 > 500ms     |
| `attic_storage_bytes`           | Gauge     | Current storage usage | > 90% capacity  |
| `attic_cache_hits_total`        | Counter   | Cache hits            | N/A (ratio)     |
| `attic_cache_misses_total`      | Counter   | Cache misses          | N/A (ratio)     |
| `attic_gc_runs_total`           | Counter   | GC executions         | 0 in 24h        |

#### PostgreSQL Metrics (CNPG)

| Metric                            | Type    | Description               | Alert Threshold |
| --------------------------------- | ------- | ------------------------- | --------------- |
| `cnpg_collector_up`               | Gauge   | Cluster health            | == 0 for 2m     |
| `cnpg_pg_replication_lag`         | Gauge   | Replication lag (seconds) | > 60s for 5m    |
| `cnpg_backends_total`             | Gauge   | Active connections        | > 80% max       |
| `cnpg_pg_stat_database_deadlocks` | Counter | Deadlock count            | > 5 in 5m       |

### Service Level Objectives (SLOs)

#### SLO Targets

**Availability SLO:**

| Window          | Target | Error Budget  |
| --------------- | ------ | ------------- |
| Rolling 30 days | 99.9%  | 43.2 minutes  |
| Rolling 7 days  | 99.9%  | 10.08 minutes |
| Rolling 1 day   | 99.5%  | 7.2 minutes   |

**Rationale**: Nix builds can tolerate brief cache unavailability by falling back to building from source. However, prolonged outages significantly impact CI/CD pipelines.

**Latency SLO:**

| Operation    | Target  | Percentile |
| ------------ | ------- | ---------- |
| Cache hits   | < 500ms | p99        |
| Cache info   | < 200ms | p99        |
| Cache misses | < 1s    | p99        |
| NAR uploads  | < 30s   | p99        |

**Error Rate SLO:**

| Window            | Target  |
| ----------------- | ------- |
| Rolling 5 minutes | < 0.1%  |
| Rolling 1 hour    | < 0.05% |
| Rolling 1 day     | < 0.01% |

#### Alerting Thresholds

**Availability Alerts:**

| Alert                      | Condition                     | Severity |
| -------------------------- | ----------------------------- | -------- |
| AtticSLOAvailabilityBreach | Availability < 99.9% for 5m   | Critical |
| AtticAvailabilityWarning   | Availability < 99.95% for 15m | Warning  |
| AtticErrorBudgetLow        | Error budget < 25% remaining  | Warning  |
| AtticErrorBudgetCritical   | Error budget < 10% remaining  | Critical |

**Latency Alerts:**

| Alert                    | Condition                            | Severity |
| ------------------------ | ------------------------------------ | -------- |
| AtticSLOLatencyBreach    | p99 cache hit latency > 500ms for 5m | Warning  |
| AtticHighLatencyCritical | p99 latency > 2s for 5m              | Critical |

### Operational Runbook

#### Quick Reference

**Kubernetes Resources:**

| Resource           | Name      | Namespace |
| ------------------ | --------- | --------- |
| Namespace          | nix-cache | -         |
| API Deployment     | attic     | nix-cache |
| GC Deployment      | attic-gc  | nix-cache |
| PostgreSQL Cluster | attic-pg  | nix-cache |
| Service            | attic     | nix-cache |
| Ingress            | attic     | nix-cache |
| HPA                | attic     | nix-cache |

**Quick Commands:**

```bash
# Check deployment status
kubectl get pods -n nix-cache

# View API logs
kubectl logs -n nix-cache -l app.kubernetes.io/name=attic --tail=100

# Check HPA
kubectl get hpa -n nix-cache

# PostgreSQL status
kubectl get cluster attic-pg -n nix-cache

# Get CI token
kubectl get secret attic-ci-tokens -n nix-cache -o jsonpath='{.data.gitlab-myrepo}' | base64 -d | jq -r '.secret'
```

#### Common Operations

**Create New Cache:**

```bash
attic cache create my-new-cache --public
```

**Generate CI Token:**

```bash
./scripts/generate-ci-token.sh gitlab-my-repo push,pull main
```

**Scale API Replicas:**

```bash
# Manual scaling (temporary, HPA will override)
kubectl scale deployment attic -n nix-cache --replicas=5

# Update HPA limits
kubectl patch hpa attic -n nix-cache --patch '{"spec":{"maxReplicas":15}}'
```

**Restart Deployments:**

```bash
# Restart API (rolling restart)
kubectl rollout restart deployment/attic -n nix-cache

# Wait for rollout to complete
kubectl rollout status deployment/attic -n nix-cache --timeout=300s
```

#### Troubleshooting

**Pod Not Starting:**

```bash
# Check pod events
kubectl describe pod <pod-name> -n nix-cache

# Check resource constraints
kubectl describe node | grep -A10 "Allocated resources"

# Check PVC status (for PostgreSQL)
kubectl get pvc -n nix-cache
```

**API Returning 500 Errors:**

```bash
# Check API logs
kubectl logs -n nix-cache -l app.kubernetes.io/name=attic --tail=100

# Test database connectivity
kubectl exec -it attic-pg-1 -n nix-cache -- pg_isready
```

**Database Connection Issues:**

```bash
# Check PostgreSQL status
kubectl get cluster attic-pg -n nix-cache -o yaml

# Check PostgreSQL pods
kubectl get pods -n nix-cache -l cnpg.io/cluster=attic-pg

# Test connection from within cluster
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://user:pass@attic-pg-rw:5432/attic"
```

**S3 Upload Failures:**

```bash
# Check S3 configuration
kubectl get configmap attic-config -n nix-cache -o jsonpath='{.data.server\.toml}'

# Verify S3 credentials
kubectl get secret attic-secrets -n nix-cache -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d
```

## CI Integration Examples

### GitLab CI

```yaml
variables:
  NIX_CONFIG: |
    experimental-features = nix-command flakes
    accept-flake-config = true

.nix_base:
  image: nixos/nix:latest
  before_script:
    - nix profile install nixpkgs#attic-client
    - attic login production https://nix-cache.example.com $ATTIC_TOKEN
    - attic use main

build:
  extends: .nix_base
  script:
    - nix build .#default
    - attic push main result
```

**Required CI/CD Variables:**

- `ATTIC_TOKEN`: Your authentication token (masked, protected)

### GitHub Actions

```yaml
name: Nix Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v27
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
            accept-flake-config = true

      - name: Setup Attic
        run: |
          nix profile install nixpkgs#attic-client
          attic login production https://nix-cache.example.com "${{ secrets.ATTIC_TOKEN }}"
          attic use main

      - name: Build
        run: nix build .#default

      - name: Push to Cache
        run: attic push main result
```

**Required Secrets:**

- `ATTIC_TOKEN`: Your authentication token

### Woodpecker CI (Codeberg)

```yaml
steps:
  build:
    image: nixos/nix:latest
    environment:
      - NIX_CONFIG=extra-substituters = https://nix-cache.example.com/main
        extra-trusted-public-keys = main:PUBLIC_KEY_HERE
    secrets: [attic_token]
    commands:
      - nix profile install nixpkgs#attic-client
      - echo "$ATTIC_TOKEN" | attic login production https://nix-cache.example.com --set-token
      - attic use main
      - nix build .#default
      - attic push main result
```

## Best Practices

### What to Cache

**Recommended for Caching:**

| Content Type           | Example                    | Reason                  |
| ---------------------- | -------------------------- | ----------------------- |
| Build outputs          | `nix build .#package`      | Core use case           |
| Development shells     | `nix develop` dependencies | Speeds up onboarding    |
| Container images       | `nix build .#container`    | Large, slow to build    |
| CI dependencies        | Common build tools         | Reduces CI time         |
| Cross-compiled outputs | aarch64-linux on x86_64    | Very slow without cache |

**NOT Recommended for Caching:**

| Content Type              | Reason              | Alternative           |
| ------------------------- | ------------------- | --------------------- |
| Secrets/credentials       | Security risk       | Use secret management |
| `.env` files              | May contain secrets | Configure at runtime  |
| User-specific config      | Not portable        | Use home-manager      |
| Large datasets            | Fills cache quickly | Use data storage      |
| Ephemeral build artifacts | Wastes space        | Don't push            |

### Cache Key Strategies

**Maximizing Cache Hits:**

1. **Pin Nixpkgs version:**

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
}
```

2. **Use flake.lock consistently:**

```bash
# Commit flake.lock to version control
git add flake.lock
git commit -m "Pin dependencies"
```

3. **Avoid impure inputs:**

```nix
# Bad - changes every build
version = builtins.currentTime;

# Good - stable version
version = "1.0.0";
```

### Reducing Cache Size

1. **Don't cache the closure unless needed:**

```bash
# Push only the build output
attic push main result

# Instead of pushing everything
# attic push main --closure result
```

2. **Garbage collect locally first:**

```bash
nix store gc
nix build .#package
attic push main result
```

3. **Split large outputs:**

```nix
packages = {
  core = ...;      # Small, frequently used
  full = ...;      # Large, rarely needed
  docs = ...;      # Optional
};
```

### Security Considerations

1. **Use minimal permissions:**
   - Pull-only tokens for CI builds that don't push
   - Push tokens only where needed

2. **Rotate tokens regularly:**
   - Every 90 days for long-lived tokens
   - After team member departures
   - After suspected compromise

3. **Store tokens securely:**
   - Use CI/CD secret management
   - Never commit tokens to version control
   - Use environment variables, not command arguments

4. **Always use public key verification:**

```ini
trusted-public-keys = main:YOUR_PUBLIC_KEY_HERE
```

### CI/CD Integration

1. **Cache common dependencies first:**

```yaml
cache:warm:
  script:
    - nix build nixpkgs#stdenv
    - attic push main result
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
```

2. **Push only on successful builds:**

```yaml
deploy:
  script:
    - nix build .#package
    - nix flake check
    - attic push main result # Only after tests pass
```

3. **Use watch-store for comprehensive caching:**

```yaml
build:
  script:
    - attic watch-store main &
    - nix build .#package
    - kill %1 # Stop watch-store
```

## Troubleshooting

### Cache Not Being Used

**Symptoms:** Nix rebuilds packages instead of downloading from cache

**Solutions:**

1. Verify substituter is configured:

```bash
nix show-config | grep substituters
```

2. Check public key matches:

```bash
curl -s https://nix-cache.example.com/main/nix-cache-info
```

3. Test cache connectivity:

```bash
curl -I https://nix-cache.example.com/main/nix-cache-info
```

### Authentication Failures

**Error:** `Failed to authenticate with cache`

**Solutions:**

1. Verify token is valid:

```bash
attic login production https://nix-cache.example.com
# Re-enter token
```

2. Check token permissions:
   - Contact infrastructure team to verify token hasn't been revoked
   - Ensure token type matches use case (read-only tokens can't push)

3. Verify token in CI/CD:

```bash
# GitLab CI
echo $ATTIC_TOKEN | cut -c1-10
# Should show "attic_****" or JWT format
```

### Push Failures

**Error:** `Failed to push to cache`

**Solutions:**

1. Check write permissions:

```bash
# Only read-write tokens can push
attic cache info main
```

2. Verify cache exists:

```bash
attic cache list
```

3. Check network connectivity:

```bash
curl -X POST https://nix-cache.example.com/main
```

### Slow Downloads

**Symptoms:** Cache downloads slower than expected

**Solutions:**

1. Check your network connection
2. Use compression for large NARs (automatic in recent Nix versions)
3. Consider parallel downloads:

```nix
# In nix.conf
http-connections = 50
```

## Getting Started

### Prerequisites

- Kubernetes cluster (1.24+)
- kubectl configured with cluster access
- OpenTofu or Terraform (1.5+)
- S3-compatible object storage
- DNS control for your domain

### Quick Start

```bash
# 1. Clone the repository
git clone https://gitlab.com/your-org/attic-cache.git
cd attic-cache

# 2. Set required environment variables
export ATTIC_JWT_SECRET="$(openssl genrsa 4096 | base64 -w0)"

# 3. Configure terraform.tfvars
cp tofu/stacks/attic/terraform.tfvars.example tofu/stacks/attic/terraform.tfvars
# Edit terraform.tfvars with your settings

# 4. Run deployment
./scripts/deploy.sh

# 5. Initialize the cache
./scripts/init-cache.sh
```

### Configuration

Edit `tofu/stacks/attic/terraform.tfvars`:

```hcl
# Kubernetes Configuration
kubeconfig_path = "~/.kube/config"
namespace       = "nix-cache"

# Attic Configuration
attic_image     = "heywoodlh/attic:12cbeca141f46e1ade76728bce8adc447f2166c6"
attic_hostname  = "nix-cache.example.com"

# HPA Configuration
api_min_replicas = 2
api_max_replicas = 10

# PostgreSQL Configuration
pg_instances      = 3
pg_storage_size   = "10Gi"
pg_storage_class  = "standard"

# S3 Configuration
s3_endpoint    = "https://s3.example.com"
s3_bucket_name = "nix-cache"
s3_region      = "us-east-1"

# Enable backups
enable_backup       = true
backup_s3_bucket    = "nix-cache-backup"
```

### Testing

```bash
# Configure Attic CLI
attic login production https://nix-cache.example.com
# Enter your token when prompted

# Test pull from cache
nix build nixpkgs#hello

# Test push to cache (if you have write permissions)
attic push main result
```

## Cost Projection

### Example Deployment with CloudNativePG

| Component              | Specification       | Monthly Cost (Est.) |
| ---------------------- | ------------------- | ------------------- |
| API Pods (2-10)        | 512Mi, 0.5 vCPU avg | ~$15-30             |
| GC Pod (1)             | 256Mi, 0.25 vCPU    | ~$3                 |
| PostgreSQL Cluster (3) | 1Gi, 0.5 vCPU each  | ~$25-40             |
| PG Storage (3x10Gi)    | Persistent volumes  | ~$10                |
| Object Storage         | 500GB (NAR)         | ~$50                |
| Object Storage         | 500GB (PG backup)   | ~$50                |
| Load Balancer          | Shared              | ~$5                 |
| **Total**              |                     | **~$160-190/mo**    |

Note: Costs vary by cloud provider and region. These are estimates for reference.

## Related Resources

- [Attic Documentation](https://docs.attic.rs) - Official Attic documentation
- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [Nix Manual](https://nixos.org/manual/nix/stable/) - Nix reference documentation
- [HPA v2 API](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
