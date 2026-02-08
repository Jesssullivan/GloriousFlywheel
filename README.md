# Attic Cache - Self-Hosted Nix Binary Cache Infrastructure

Self-hosted [Attic](https://github.com/zhaofengli/attic) Nix binary cache with auto-scaled GitLab runner fleet and GitOps management dashboard. Deploy to any Kubernetes cluster using OpenTofu and the GitLab Kubernetes Agent.

**Features**:

- Attic binary cache with S3/MinIO storage
- Auto-scaled GitLab runners (Docker, Nix, DinD, Rocky)
- Real-time monitoring dashboard with drift detection
- GitLab OAuth authentication
- CloudNativePG for HA PostgreSQL
- Horizontal Pod Autoscaling (HPA) for all services
- Optional Bazel remote cache
- Prometheus ServiceMonitor integration

## Quick Start

**Prerequisites**: Kubernetes 1.24+, kubectl, OpenTofu, GitLab with Kubernetes Agent

```bash
# 1. Configure your organization
cp config/organization.example.yaml config/organization.yaml
# Edit with your GitLab group, cluster contexts, domains

# 2. Set up secrets
cp .env.example .env
# Add TF_HTTP_PASSWORD (GitLab PAT)

# 3. Deploy
just tofu-plan attic
just tofu-apply attic

# 4. Verify
curl https://attic-cache.{your-domain}/nix-cache-info
```

See **[Quick Start Guide](docs/quick-start.md)** for detailed setup instructions.

## Architecture

```
                      GitLab CI/CD
  validate ──> build ──> deploy ──> verify
     │            │
     │ (parallel) │ needs: [] (greedy)
     │            │
     │            ├── nix build → Attic push ─┐
     │            └── bazel build ─────────────┤ Cache flywheel
     │                                         │
     │            ┌────────────────────────────┘
     │            ▼
     │     ┌─────────────┐
     │     │ Attic Cache  │  ← subsequent builds pull from here
     │     │  (cluster)   │    60+ min → <5 min
     │     └─────────────┘
     │
     └──── GitLab Kubernetes Agent
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
     ┌────────────┐ ┌────────────┐ ┌────────────┐
     │    dev     │ │  staging   │ │    prod    │
     │  (review)  │ │  (staging) │ │(production)│
     │  *.dev.    │ │ *.staging. │ │   *.prod.  │
     │example.com │ │example.com │ │example.com │
     └────────────┘ └────────────┘ └────────────┘
```

**Example Cluster Configuration** (customize in `config/organization.yaml`):

| Cluster | Purpose    | GitLab Agent Context    | Ingress Domain      |
| ------- | ---------- | ----------------------- | ------------------- |
| dev     | Dev/review | `myorg/k8s/agents:dev`  | `*.dev.example.com` |
| prod    | Production | `myorg/k8s/agents:prod` | `*.example.com`     |

## Cache Flywheel

This infrastructure implements an incremental cache warming pattern that dramatically reduces CI build times:

```
Pipeline N (cold, no cache):
  nix build .#package           ← 60+ min (compile everything from scratch)
  attic push main result        ← push full closure to cache

Pipeline N+1 (warm, watch-store active):
  watch-store running in background
  nix build .#package           ← <5 min (derivations pulled from cache)
  each derivation pushed AS IT'S BUILT

Pipeline N+2 (fails at minute 10):
  watch-store running
  nix build .#package           ← fails partway through
  but 10 minutes of derivations are ALREADY cached
  next pipeline picks up where this one left off
```

**How it works:**

1. **Greedy builds** (`needs: []`) - Build jobs start immediately, parallel with validation
2. **Substituter pull** - Nix configured with Attic as trusted substituter
3. **Incremental push** - `attic watch-store` runs in background, pushing each store path as it's built
4. **Bootstrap** - Attic client fetched from cache if available, skipped if not
5. **Final push** - Belt-and-suspenders full closure push after build completes
6. **Non-blocking** - All cache operations are best-effort, never fail builds

See [docs/greedy-build-pattern.md](docs/greedy-build-pattern.md) for implementation details.

## OpenTofu Modules

15 reusable infrastructure modules for Kubernetes deployments:

| Module                              | Purpose                                                     |
| ----------------------------------- | ----------------------------------------------------------- |
| `hpa-deployment`                    | HPA-enabled Kubernetes deployments                          |
| `cnpg-operator` / `postgresql-cnpg` | CloudNativePG operator and PostgreSQL clusters              |
| `minio-operator` / `minio-tenant`   | MinIO operator and S3-compatible storage                    |
| `gitlab-runner`                     | Self-hosted GitLab Runner on K8s (HPA, PDB, ServiceMonitor) |
| `gitlab-user-runner`                | Automated runner token lifecycle via GitLab API             |
| `gitlab-agent-rbac`                 | RBAC for GitLab Agent ci_access impersonation               |
| `runner-security`                   | NetworkPolicy, ResourceQuota, LimitRange                    |
| `runner-dashboard`                  | SvelteKit GitOps dashboard deployment                       |
| `bazel-cache`                       | Bazel remote cache with S3/MinIO backend                    |
| `dns-record`                        | DNS record management                                       |

## Infrastructure Stacks

Three deployable stacks for complete infrastructure:

### 1. Attic Cache (`tofu/stacks/attic/`)

Deploys the complete Attic binary cache infrastructure:

- **Attic API** - Stateless API server (HPA: 1-10 replicas)
- **PostgreSQL** - CloudNativePG cluster (1 or 3 instances)
- **Storage** - MinIO distributed or external S3
- **Ingress** - TLS-enabled ingress with cert-manager
- **Optional**: Bazel remote cache, cache warming CronJob

**Deploy**:

```bash
cd tofu/stacks/attic
ENV=dev just tofu-plan
ENV=dev just tofu-apply
```

### 2. GitLab Runners (`tofu/stacks/bates-ils-runners/`)

_Note: Rename to `gitlab-runners` for generic deployments_

Auto-scaled runner fleet with 5 runner types:

| Runner   | Image            | Isolation        | Privileged | HPA Range |
| -------- | ---------------- | ---------------- | ---------- | --------- |
| `docker` | `ubuntu-22.04`   | Shared namespace | No         | 1-20      |
| `dind`   | `docker:dind`    | Shared namespace | Yes        | 1-10      |
| `nix`    | Custom Nix image | Shared namespace | No         | 1-10      |
| `rocky8` | `rockylinux:8`   | Per-job pods     | No         | 1-10      |
| `rocky9` | `rockylinux:9`   | Per-job pods     | No         | 1-10      |

**Features**:

- HPA based on CPU/memory utilization
- PodDisruptionBudget for graceful scaling
- Prometheus ServiceMonitors
- Resource quotas and limits
- Network policies (optional)

### 3. Runner Dashboard (`tofu/stacks/runner-dashboard/`)

SvelteKit web application for runner management:

**Features**:

- Real-time runner status and metrics
- GitLab OAuth authentication
- Drift detection (tfvars vs Kubernetes state)
- GitOps workflow (create MRs for config changes)
- Server-Sent Events for live updates
- Chart.js visualizations

**Access**: `https://runner-dashboard.{your-domain}`

## CI/CD Pipeline

GitLab CI/CD pipeline with 4 stages:

```yaml
stages:
  - validate # Lint, format, security scans
  - build # Nix builds, Bazel builds, Docker images
  - deploy # Deploy to review/staging/production
  - verify # Health checks, smoke tests
```

**Environment mapping**:

- **Review** (beehive/dev) - Merge requests
- **Staging** (rigel/staging) - `main` branch
- **Production** (rigel/prod) - Semver tags (`v1.2.3`)

**Components published** for downstream projects:

```yaml
# In your project's .gitlab-ci.yml
include:
  - component: gitlab.com/yourorg/attic-iac/nix-build@main
    inputs:
      attic_cache: main
      attic_server: https://attic-cache.example.com

  - component: gitlab.com/yourorg/attic-iac/docker-build@main

  - component: gitlab.com/yourorg/attic-iac/k8s-deploy@main
```

## Project Structure

```
├── config/
│   ├── organization.yaml           # Your org config (gitignored)
│   └── organization.example.yaml   # Template
├── tofu/
│   ├── modules/                    # Reusable OpenTofu modules (15)
│   └── stacks/                     # Deployable stacks (3)
│       ├── attic/
│       ├── bates-ils-runners/      # Rename to gitlab-runners
│       └── runner-dashboard/
├── app/                            # Runner dashboard (SvelteKit 5)
│   ├── src/
│   ├── scripts/
│   └── tests/
├── scripts/                        # Helper scripts
│   ├── generate-attic-token.sh
│   ├── validate-org-config.sh
│   └── lib/
├── examples/                       # CI/CD component examples
│   ├── nix-project/
│   ├── docker-project/
│   └── k8s-deploy-project/
├── docs/                           # Documentation
│   ├── quick-start.md
│   ├── customization-guide.md
│   ├── greedy-build-pattern.md
│   └── runners/                    # Runner documentation (12 files)
├── .gitlab-ci.yml                  # Main CI/CD pipeline
├── Justfile                        # Task runner
├── flake.nix                       # Nix flake
└── MODULE.bazel                    # Bazel workspace
```

## Development

### Prerequisites

- Nix with flakes enabled
- direnv (recommended)
- just (task runner)
- pnpm (for dashboard development)

### Local Setup

```bash
# Load Nix devShell
direnv allow

# Run checks
just check

# Build Nix packages
nix build .#attic-client
nix build .#container

# Build dashboard
cd app
pnpm install
pnpm dev
```

### Common Tasks

```bash
just                        # List all commands
just check                  # Run all validations
just tofu-plan <stack>      # Plan Tofu deployment
just tofu-apply <stack>     # Apply Tofu deployment
just proxy-up               # Start SOCKS proxy (if configured)
just bk get pods            # kubectl through proxy
```

## Configuration

All configuration is centralized in `config/organization.yaml`:

```yaml
organization:
  name: myorg
  full_name: "My Organization"
  group_path: mygroup # GitLab group path

gitlab:
  url: https://gitlab.com
  project_id: "12345678" # Project for Terraform state
  agent_group: mygroup/k8s/agents

clusters:
  - name: dev
    role: development
    domain: dev.example.com
    context: mygroup/k8s/agents:dev

namespaces:
  attic:
    dev: attic-cache-dev
    prod: attic-cache
  runners:
    all: gitlab-runners
```

See [Customization Guide](docs/customization-guide.md) for detailed options.

## Monitoring

### Prometheus Integration

All services export Prometheus metrics via ServiceMonitors:

- **Attic API** - Request rate, latency, cache hits
- **PostgreSQL** - Connections, queries, replication lag
- **MinIO** - Throughput, storage usage
- **Runners** - Job queue depth, execution time

### Runner Dashboard

Real-time monitoring UI at `https://runner-dashboard.{your-domain}`:

- Live runner status and metrics
- HPA scaling visualization
- Drift detection
- Config management

## Troubleshooting

### Common Issues

**Pods stuck in Pending**:

```bash
kubectl get pvc -n {namespace}
kubectl describe pvc {name} -n {namespace}
```

**Ingress not accessible**:

```bash
kubectl get ingress -n {namespace}
kubectl get certificate -n {namespace}
```

**PostgreSQL init failures**:

```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

See [comprehensive troubleshooting guide](docs/runners/troubleshooting.md) for more.

## Documentation

- **[Quick Start Guide](docs/quick-start.md)** - Get up and running in 30 minutes
- **[Customization Guide](docs/customization-guide.md)** - Adapt for your organization
- **[Greedy Build Pattern](docs/greedy-build-pattern.md)** - Understanding the cache flywheel
- **[Runners Documentation](docs/runners/)** - 12 guides covering all aspects of runner management

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Support

- **Issues**: https://github.com/Jesssullivan/attic-iac/issues
- **Discussions**: https://github.com/Jesssullivan/attic-iac/discussions

## License

Apache 2.0

## Credits

Originally developed for Tinyland.dev infrastructure. Open sourced for community use.
