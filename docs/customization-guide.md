# Customization Guide

Comprehensive guide to customizing attic-cache infrastructure for your organization's needs.

## Table of Contents

1. [Organization Configuration](#organization-configuration)
2. [Storage Backend Choices](#storage-backend-choices)
3. [Database Configuration](#database-configuration)
4. [Runner Configuration](#runner-configuration)
5. [Network Configuration](#network-configuration)
6. [Monitoring Integration](#monitoring-integration)
7. [Feature Flags](#feature-flags)

---

## Organization Configuration

The `config/organization.yaml` file is your single source of truth for organization-wide settings.

### Cluster Configuration

Define one or more Kubernetes clusters:

```yaml
clusters:
  - name: dev # Internal identifier (used in ENV variable)
    role: development # Role: development, staging, production
    domain: dev.example.com # Base domain for ingress
    context: mygroup/k8s/agents:dev # GitLab Agent context
```

**Best practices**:

- Use `dev`, `staging`, `prod` for standard 3-tier setup
- Or `dev`, `prod` for simpler 2-tier deployment
- Single-cluster: Just `prod` is fine for small teams

### Namespace Naming

Configure namespace patterns:

```yaml
namespaces:
  attic:
    dev: attic-cache-dev
    staging: attic-cache-staging
    prod: attic-cache
  runners:
    all: gitlab-runners # Same namespace across all clusters
```

**Options**:

- **Shared namespace**: `runners.all` uses same name everywhere
- **Per-environment**: Override in tfvars with `namespace = "gitlab-runners-dev"`
- **Per-team**: Use separate namespaces for different teams

---

## Storage Backend Choices

Choose between self-hosted MinIO or external S3-compatible storage.

### Option 1: MinIO (Recommended for Getting Started)

**Pros**:

- No external dependencies
- Lower latency (in-cluster)
- Full control over data
- Cost-effective for high throughput

**Cons**:

- Requires cluster storage capacity
- Additional operational complexity
- Not suitable for multi-cluster sharing

**Configuration** (`tofu/stacks/attic/dev.tfvars`):

```hcl
use_minio = true

# Single-server MinIO (simple, for dev)
minio_distributed_mode = false
minio_volume_size      = "20Gi"

# OR: Distributed MinIO (HA, for production)
minio_distributed_mode = true  # 4 servers × 4 drives
minio_volume_size      = "100Gi"  # Per drive

minio_cpu_request      = "100m"
minio_memory_request   = "256Mi"
```

**When to use distributed mode**:

- Production workloads with HA requirements
- High throughput (>1000 builds/day)
- Need for data redundancy
- Multiple clusters sharing cache (via external ingress)

### Option 2: External S3 (AWS, Civo, DigitalOcean, etc.)

**Pros**:

- No cluster storage needed
- Managed service reliability
- Easy multi-cluster sharing
- Built-in redundancy and backups

**Cons**:

- Network latency for cache operations
- Ongoing cloud costs
- External dependency

**Configuration** (`tofu/stacks/attic/dev.tfvars`):

```hcl
use_minio = false

s3_endpoint        = "https://s3.us-east-1.amazonaws.com"
s3_region          = "us-east-1"
s3_bucket_name     = "my-attic-cache"
# s3_access_key_id and s3_secret_access_key set via env vars or CI variables
```

**Set credentials** (don't commit these):

```bash
# Local development (replace with your actual credentials)
export TF_VAR_s3_access_key_id=YOUR_ACCESS_KEY_HERE
export TF_VAR_s3_secret_access_key=YOUR_SECRET_KEY_HERE

# GitLab CI/CD (set as masked variables in GitLab UI)
# S3_ACCESS_KEY_ID=<your-key>
# S3_SECRET_ACCESS_KEY=<your-secret>
```

### Option 3: Hybrid (Multiple Caches)

Deploy separate Attic instances per cluster with cluster-local MinIO, then use Attic's upstream feature to share between them.

---

## Database Configuration

PostgreSQL is required for Attic metadata. Choose between standalone and high-availability modes.

### Standalone PostgreSQL (Development)

**Use for**:

- Development environments
- Low-traffic deployments
- Cost-sensitive setups

**Configuration**:

```hcl
use_cnpg_postgres = true
pg_instances      = 1          # Single instance
pg_storage_size   = "10Gi"
pg_enable_backup  = false      # No backups in dev

pg_cpu_request    = "250m"
pg_memory_request = "512Mi"
```

### High-Availability PostgreSQL (Production)

**Use for**:

- Production workloads
- Multi-user environments
- SLA requirements

**Configuration**:

```hcl
use_cnpg_postgres = true
pg_instances      = 3          # 3-node cluster (1 primary + 2 replicas)
pg_storage_size   = "50Gi"
pg_storage_class  = "fast-ssd"  # Use fast storage class

# Resource sizing for production
pg_cpu_request    = "500m"
pg_cpu_limit      = "2000m"
pg_memory_request = "1Gi"
pg_memory_limit   = "2Gi"

# Database tuning
pg_max_connections = 200
pg_shared_buffers  = "512MB"
```

### PostgreSQL Backups

**Enable backups** for production:

```hcl
pg_enable_backup      = true
pg_backup_retention   = "30d"     # Keep 30 days of backups
pg_backup_schedule    = "0 2 * * *"  # Daily at 2 AM
pg_backup_bucket_name = "my-attic-pg-backups"
```

**Backup storage**: Uses same S3/MinIO as Attic cache.

### External PostgreSQL (Neon, AWS RDS, etc.)

**Use for**:

- Serverless deployments
- Multi-region setups
- Managed service preference

**Configuration**:

```hcl
use_cnpg_postgres = false
database_url      = "postgresql://user:password@host:5432/attic?sslmode=require"
```

**Important**: URL-encode the password if it contains special characters:

```bash
# Bad:  password with @ symbol
postgresql://user:p@ssw0rd@host/db

# Good: URL-encoded
postgresql://user:p%40ssw0rd@host/db
```

---

## Runner Configuration

Configure auto-scaled GitLab runners for different workload types.

### Runner Types

Five runner types are available:

| Runner   | Use Case                    | Isolation        | Privileged |
| -------- | --------------------------- | ---------------- | ---------- |
| `docker` | Docker builds               | Shared namespace | No         |
| `dind`   | Docker-in-Docker builds     | Shared namespace | Yes        |
| `nix`    | Nix builds with Attic cache | Shared namespace | No         |
| `rocky8` | Rocky Linux 8 builds        | Per-job pods     | No         |
| `rocky9` | Rocky Linux 9 builds        | Per-job pods     | No         |

### Enable/Disable Runners

Control which runners to deploy:

```hcl
deploy_docker_runner = true
deploy_dind_runner   = true
deploy_nix_runner    = true
deploy_rocky8_runner = false  # Disable if not needed
deploy_rocky9_runner = false
```

### Scaling Configuration

**Per-runner HPA settings**:

```hcl
# Docker runner scaling
docker_min_replicas = 1
docker_max_replicas = 10
docker_cpu_target_percent    = 70
docker_memory_target_percent = 80

# Nix runner scaling (typically needs fewer replicas)
nix_min_replicas = 1
nix_max_replicas = 5
```

**Scaling decision guide**:

- **Small team** (< 10 devs): `min=1, max=5` for each runner type
- **Medium team** (10-50 devs): `min=2, max=20`
- **Large team** (50+ devs): `min=5, max=50`

**Resource limits**:

```hcl
docker_cpu_request = "500m"
docker_cpu_limit   = "2000m"
docker_memory_request = "1Gi"
docker_memory_limit   = "4Gi"
```

### Runner Tags

Runners are tagged for job selection:

```yaml
# In .gitlab-ci.yml
build:
  tags:
    - docker # Uses docker runner
    - kubernetes
```

Available tags:

- `docker` - Standard Docker builds
- `dind` - Docker-in-Docker (for building images)
- `nix` - Nix builds with Attic integration
- `rocky8`, `rocky9` - OS-specific builds

---

## Network Configuration

### Proxy Configuration

For clusters behind corporate firewalls:

```yaml
# In organization.yaml
network:
  proxy_host: proxy.corp.internal
  proxy_port: 3128
```

This configures:

- SOCKS proxy for local development (`just proxy-up`)
- HTTP_PROXY/HTTPS_PROXY for runners
- NO_PROXY exceptions for cluster-internal traffic

### Ingress Configuration

**TLS/SSL**:

```hcl
enable_tls           = true
cert_manager_issuer  = "letsencrypt-prod"  # Or your CA issuer
```

**Ingress class**:

```hcl
ingress_class = "traefik"  # Or "nginx", "haproxy", etc.
```

**Custom domains**:

```hcl
ingress_host = "cache.mycompany.com"  # Override default
```

### Network Policies

**Enable** for security:

```hcl
pg_enable_network_policy = true
```

**Known issue**: Disabled by default for K3s due to API server egress requirements during PostgreSQL init.

---

## Monitoring Integration

### Prometheus Integration

**Enable ServiceMonitors**:

```hcl
enable_prometheus_monitoring = true
```

Exports metrics for:

- Attic API (request rate, latency, cache hits)
- PostgreSQL (connections, queries, replication lag)
- MinIO (throughput, storage usage)
- Runners (job queue, execution time)

### Runner Dashboard

Optional web UI for runner management:

```hcl
# Deploy dashboard
deploy_runner_dashboard = true
```

**Features**:

- Real-time runner status
- GitLab OAuth authentication
- Drift detection (tfvars vs K8s state)
- Config management (create MRs for changes)

**Configuration** (in dashboard stack):

```hcl
gitlab_oauth_client_id     = var.gitlab_oauth_client_id
gitlab_oauth_client_secret = var.gitlab_oauth_client_secret  # Set via env var
prometheus_url             = "http://prometheus.monitoring.svc:9090"
```

---

## Feature Flags

### Bazel Remote Cache

**Enable** if using Bazel:

```hcl
enable_bazel_cache     = true
bazel_cache_max_size_gb = 100
```

Uses same MinIO/S3 backend as Attic.

### Cache Warming

**Enable** to pre-populate common dependencies:

```hcl
enable_cache_warming = true
```

Runs nightly CronJob to build common flake inputs (nixpkgs, rust, python, etc).

### GitOps Mode

**Enable** for infrastructure-as-code runner management:

```hcl
enable_gitops_workflow = true
```

Allows dashboard to create MRs for runner config changes instead of direct kubectl modifications.

---

## Environment-Specific Overrides

Create separate tfvars for each environment:

```bash
tofu/stacks/attic/
├── dev.tfvars        # Development config
├── staging.tfvars    # Staging config
└── prod.tfvars       # Production config
```

**Example progression**:

**dev.tfvars** (minimal):

```hcl
pg_instances = 1
minio_distributed_mode = false
api_min_replicas = 1
```

**staging.tfvars** (mid-size):

```hcl
pg_instances = 1
minio_distributed_mode = false
api_min_replicas = 2
api_max_replicas = 5
```

**prod.tfvars** (HA):

```hcl
pg_instances = 3
minio_distributed_mode = true
api_min_replicas = 3
api_max_replicas = 20
pg_enable_backup = true
```

---

## Common Customization Scenarios

### Scenario 1: Small Team, Single Cluster

```yaml
# organization.yaml
clusters:
  - name: prod
    role: production
    domain: k8s.mycompany.com
    context: mygroup/k8s/agents:prod
```

```hcl
# prod.tfvars
pg_instances = 1
use_minio = true
minio_distributed_mode = false
api_min_replicas = 1
api_max_replicas = 3
deploy_docker_runner = true
deploy_nix_runner = true
deploy_dind_runner = false
```

### Scenario 2: Medium Team, Dev + Prod

Use example from Quick Start with 2 clusters.

### Scenario 3: Large Team, Full Pipeline

Use `config/organization-ha.example.yaml` with 3 clusters and full HA configuration.

### Scenario 4: Multi-Region

Deploy separate stacks per region, use S3 cross-region replication for cache sharing.

---

## Next Steps

- Review [Quick Start Guide](quick-start.md) for initial deployment
- See [Module Reference](module-reference.md) for detailed variable docs
- Check [Troubleshooting](runners/troubleshooting.md) for common issues
