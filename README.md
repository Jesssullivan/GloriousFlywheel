# Attic Cache - Bates ILS Infrastructure Platform

Self-hosted [Attic](https://github.com/zhaofengli/attic) Nix binary cache, GitLab runner fleet, and supporting infrastructure deployed to Bates College Kubernetes clusters via GitLab CI/CD and the GitLab Kubernetes Agent. No authentication -- public read/write on the internal Bates network.

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
     │     │ (beehive)    │    60+ min → <5 min
     │     └─────────────┘
     │
     └──── GitLab Kubernetes Agent
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
     ┌────────────┐ ┌────────────┐ ┌────────────┐
     │  beehive   │ │   rigel    │ │   rigel    │
     │  (review)  │ │ (staging)  │ │(production)│
     │ *.beehive. │ │ *.rigel.   │ │ *.rigel.   │
     │  bates.edu │ │  bates.edu │ │  bates.edu │
     └────────────┘ └────────────┘ └────────────┘
```

**Clusters:**

| Cluster | Purpose            | GitLab Agent                                          | Domain                |
| ------- | ------------------ | ----------------------------------------------------- | --------------------- |
| beehive | Dev/review         | `bates-ils/projects/kubernetes/gitlab-agents:beehive` | `*.beehive.bates.edu` |
| rigel   | Staging/production | `bates-ils/projects/kubernetes/gitlab-agents:rigel`   | `*.rigel.bates.edu`   |

## Cache Flywheel

This repo dogfoods its own Attic binary cache. The flywheel ensures every
CI build -- even partial/failed ones -- populates the cache incrementally:

```
Pipeline N (cold, no cache):
  nix build .#attic-client     ← 60+ min (compile Rust, Nix from scratch)
  attic push main result       ← push full closure to cache at the end

Pipeline N+1 (warm, watch-store active):
  watch-store running in background
  nix build .#attic-client     ← <5 min (intermediate derivations pulled from cache)
  each derivation pushed to cache AS IT'S BUILT

Pipeline N+2 (fails at minute 10):
  watch-store running
  nix build .#container        ← fails partway through
  but 10 minutes of derivations are ALREADY cached
  next pipeline picks up where this one left off
```

**How it works:**

1. **Greedy builds** (`needs: []`) -- build jobs start immediately, parallel with validation
2. **Substituter pull** -- before_script adds `extra-substituters` + `trusted-substituters` for Attic
3. **Incremental push** -- `attic watch-store` runs in the background, pushing each store path to the cache as Nix builds it. Even if the build fails, all completed derivations are preserved.
4. **Bootstrap** -- watch-store needs the attic client. We try `nix build .#attic-client --max-jobs 0` (substituters only). If cached: instant, watch-store starts. If not cached (first pipeline): skipped, falls back to end-of-build push.
5. **Final push** -- belt-and-suspenders closure push of the result symlink after build completes
6. **Auth-free** -- Attic runs without authentication on the internal network
7. **Non-blocking** -- all cache operations are best-effort, never fail the build

The same pattern applies to the Bazel remote cache for OpenTofu validation.
See [docs/greedy-build-pattern.md](docs/greedy-build-pattern.md) for details.

**OpenTofu Modules:**

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

## Quick Start

### Use the Cache

Add the cache as a Nix substituter:

```nix
# In nix.conf
substituters = https://attic-cache.rigel.bates.edu https://cache.nixos.org
trusted-substituters = https://attic-cache.rigel.bates.edu

# Or in flake.nix
{
  nixConfig = {
    extra-substituters = [ "https://attic-cache.rigel.bates.edu" ];
    extra-trusted-substituters = [ "https://attic-cache.rigel.bates.edu" ];
  };
}
```

### Push to Cache (CI/CD)

Builds use the greedy pattern -- push immediately, fail silently:

```yaml
nix:build:
  script:
    - nix build .#mypackage --out-link result
    - nix run .#attic -- push main result || echo "Cache push (non-blocking)"
```

## CI/CD Pipeline

### Stages

`validate` -> `build` -> `test` -> `deploy` -> `verify`

- **validate**: `nix flake check`, OpenTofu `fmt`/`validate`, SAST, secret detection
- **build**: `nix build` with greedy cache push
- **test**: Security scanning (SAST template)
- **deploy**: `tofu plan` + `tofu apply` per environment
- **verify**: Health check (`/nix-cache-info` endpoint)

### Environment Mapping

| Trigger       | Environment | Cluster | Auto-deploy |
| ------------- | ----------- | ------- | ----------- |
| Merge request | review      | beehive | Yes         |
| `main` branch | staging     | rigel   | Yes         |
| `v*.*.*` tag  | production  | rigel   | Manual      |

### CI/CD Variables

With MinIO (default), S3 variables are **not required**.

| Variable               | Description                       | Required                     |
| ---------------------- | --------------------------------- | ---------------------------- |
| `KUBE_CONTEXT`         | Set automatically per environment | No (auto)                    |
| `S3_ENDPOINT`          | S3 endpoint URL                   | Only if `use_minio=false`    |
| `S3_ACCESS_KEY_ID`     | S3 access key (masked)            | Only if `use_minio=false`    |
| `S3_SECRET_ACCESS_KEY` | S3 secret key (masked)            | Only if `use_minio=false`    |
| `S3_BUCKET_NAME`       | S3 bucket name                    | Only if `use_minio=false`    |
| `RUNNER_TOKEN`         | GitLab Runner registration token  | Only for self-hosted runners |

## Infrastructure

### OpenTofu Stack

All infrastructure is defined in `tofu/stacks/attic/`:

```
tofu/stacks/attic/
├── main.tf            # Main configuration
├── variables.tf       # Variable definitions
├── backend.tf         # GitLab managed state backend
├── beehive.tfvars     # Dev cluster config
└── rigel.tfvars       # Prod cluster config
```

State is managed by [GitLab-managed Terraform state](https://docs.gitlab.com/ee/user/infrastructure/iac/).

### Storage (MinIO)

Both clusters use MinIO for S3-compatible storage by default (`use_minio=true`):

| Environment   | Mode            | Drives  | Total Storage |
| ------------- | --------------- | ------- | ------------- |
| beehive (dev) | Standalone      | 1x10Gi  | 10Gi          |
| rigel (prod)  | Distributed 4x4 | 16x50Gi | 800Gi raw     |

To use external S3 instead, set `use_minio=false` in your tfvars and configure the S3 CI/CD variables above.

### Manual Deployment

For local testing (requires GitLab Agent access):

```bash
cd tofu/stacks/attic

# Development (beehive)
tofu init
tofu plan -var-file=beehive.tfvars
tofu apply -var-file=beehive.tfvars

# Production (rigel)
tofu plan -var-file=rigel.tfvars
tofu apply -var-file=rigel.tfvars
```

## Stacks

| Stack               | Purpose                          | Environments   |
| ------------------- | -------------------------------- | -------------- |
| `attic`             | Attic cache + PostgreSQL + MinIO | beehive, rigel |
| `bates-ils-runners` | GitLab runner fleet (5 types)    | beehive, rigel |
| `runner-dashboard`  | SvelteKit GitOps dashboard       | beehive        |
| `gitlab-runners`    | Legacy project-level runners     | beehive        |

## Runner Fleet

Five runner types with HPA auto-scaling, PDB, and Prometheus monitoring.
Any `bates-ils` project can use runners via tags:

| Type   | Tags                           | Use Case                    |
| ------ | ------------------------------ | --------------------------- |
| docker | `docker`, `linux`, `amd64`     | General CI                  |
| dind   | `docker`, `dind`, `privileged` | Container image builds      |
| rocky8 | `rocky8`, `rhel8`, `linux`     | RHEL 8 compatibility        |
| rocky9 | `rocky9`, `rhel9`, `linux`     | RHEL 9 compatibility        |
| nix    | `nix`, `flakes`                | Nix builds with Attic cache |

See [docs/runners/](docs/runners/) for enrollment, security model, and runbook.

## CI/CD Components

Reusable job templates published as [GitLab CI/CD Components](https://docs.gitlab.com/ee/ci/components/):

```yaml
include:
  - component: $CI_SERVER_FQDN/bates-ils/projects/iac/attic-cache/docker-job@main
    inputs:
      stage: build
      image: node:20-alpine
```

Available: `docker-job`, `dind-job`, `rocky8-job`, `rocky9-job`, `nix-job`,
`docker-build`, `k8s-deploy`. See [docs/runners/self-service-enrollment.md](docs/runners/self-service-enrollment.md).

## Bazel Dogfooding

OpenTofu modules are validated incrementally using custom Bazel rules:

```bash
# Validate all modules
nix develop --command bazel build //tofu/modules:all_validate

# Validate specific module
nix develop --command bazel build //tofu/modules:bazel_cache_validate

# Run format tests
nix develop --command bazel test //tofu/modules:all_fmt_test
```

CI runs affected-only validation (only changed modules are validated in MRs).

## Development

Prerequisites: Nix with flakes enabled, direnv (recommended).

```bash
# Enter development shell
nix develop          # or: direnv allow

# Format code
nix fmt

# Validate everything
nix flake check

# Runner dashboard
cd app && pnpm install && pnpm dev
```

### Project Structure

```
.
├── .gitlab-ci.yml              # CI/CD pipeline
├── .gitlab/ci/jobs/            # CI job definitions (7 files)
├── flake.nix                   # Nix devShell, OCI images, checks
├── MODULE.bazel                # Bazel module (rules_js, rules_nixpkgs)
├── app/                        # Runner Dashboard (SvelteKit 5)
│   ├── src/routes/             # Pages: /, /runners, /monitoring, /gitops, /settings
│   └── src/lib/server/         # GitLab, Prometheus, K8s clients
├── build/tofu/                 # Custom Bazel rules for OpenTofu
├── templates/                  # CI/CD Components (7 templates)
├── ci-templates/               # Legacy CI templates (deprecated)
├── tofu/
│   ├── modules/                # 12 reusable OpenTofu modules
│   │   ├── hpa-deployment/
│   │   ├── cnpg-operator/
│   │   ├── postgresql-cnpg/
│   │   ├── minio-operator/
│   │   ├── minio-tenant/
│   │   ├── gitlab-runner/      # HPA, PDB, ServiceMonitor, alerts
│   │   ├── gitlab-user-runner/ # Token automation
│   │   ├── gitlab-agent-rbac/  # ci_access RBAC
│   │   ├── runner-security/    # NetworkPolicy, quotas
│   │   ├── runner-dashboard/
│   │   ├── bazel-cache/
│   │   └── dns-record/
│   └── stacks/
│       ├── attic/              # Attic cache deployment
│       ├── bates-ils-runners/  # Runner fleet (beehive + rigel)
│       ├── runner-dashboard/   # Dashboard deployment
│       └── gitlab-runners/     # Legacy runners
├── k8s/                        # Raw K8s manifests + cleanup CronJob
├── scripts/                    # Operational scripts
│   ├── runner-health-check.sh
│   ├── cache-warm.sh
│   └── health-check.sh
├── tests/                      # Integration + security tests
└── docs/
    ├── greedy-build-pattern.md
    ├── runners/                # Enrollment, security, runbook, HPA tuning
    └── monitoring/
```

## Troubleshooting

```bash
# Attic health check
curl https://attic-cache.beehive.bates.edu/nix-cache-info

# Runner fleet health
./scripts/runner-health-check.sh

# View Attic logs
kubectl logs -n attic-cache -l app.kubernetes.io/name=attic -f

# MinIO status
kubectl get tenant -n attic-cache
```

## License

Internal Bates College use only.
