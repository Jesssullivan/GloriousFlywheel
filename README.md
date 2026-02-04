# Attic Cache - Bates ILS Nix Binary Cache

Self-hosted [Attic](https://github.com/zhaofengli/attic) Nix binary cache deployed to Bates College Kubernetes clusters via GitLab CI/CD and the GitLab Kubernetes Agent. No authentication -- public read/write on the internal Bates network.

## Architecture

```
                      GitLab CI/CD
  validate ──> build ──> deploy ──> verify
                           │
                           │ GitLab Kubernetes Agent
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

| Cluster | Purpose | GitLab Agent | Domain |
|---------|---------|-------------|--------|
| beehive | Dev/review | `bates-ils/projects/kubernetes/gitlab-agents:beehive` | `*.beehive.bates.edu` |
| rigel | Staging/production | `bates-ils/projects/kubernetes/gitlab-agents:rigel` | `*.rigel.bates.edu` |

**OpenTofu Modules:**

| Module | Purpose |
|--------|---------|
| `hpa-deployment` | HPA-enabled Kubernetes deployments |
| `cnpg-operator` / `postgresql-cnpg` | CloudNativePG operator and PostgreSQL clusters |
| `minio-operator` / `minio-tenant` | MinIO operator and S3-compatible storage |
| `gitlab-runner` | Self-hosted GitLab Runner on Kubernetes |

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

| Trigger | Environment | Cluster | Auto-deploy |
|---------|-------------|---------|-------------|
| Merge request | review | beehive | Yes |
| `main` branch | staging | rigel | Yes |
| `v*.*.*` tag | production | rigel | Manual |

### CI/CD Variables

With MinIO (default), S3 variables are **not required**.

| Variable | Description | Required |
|----------|-------------|----------|
| `KUBE_CONTEXT` | Set automatically per environment | No (auto) |
| `S3_ENDPOINT` | S3 endpoint URL | Only if `use_minio=false` |
| `S3_ACCESS_KEY_ID` | S3 access key (masked) | Only if `use_minio=false` |
| `S3_SECRET_ACCESS_KEY` | S3 secret key (masked) | Only if `use_minio=false` |
| `S3_BUCKET_NAME` | S3 bucket name | Only if `use_minio=false` |
| `RUNNER_TOKEN` | GitLab Runner registration token | Only for self-hosted runners |

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

| Environment | Mode | Drives | Total Storage |
|-------------|------|--------|---------------|
| beehive (dev) | Standalone | 1x10Gi | 10Gi |
| rigel (prod) | Distributed 4x4 | 16x50Gi | 800Gi raw |

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

## Development

Prerequisites: Nix with flakes enabled, direnv (recommended).

```bash
# Enter development shell
nix develop          # or: direnv allow

# Format code
nix fmt

# Validate everything
nix flake check

# Validate OpenTofu
cd tofu/stacks/attic
tofu init -backend=false
tofu validate
```

### Project Structure

```
.
├── .gitlab-ci.yml              # CI/CD pipeline
├── .gitlab/ci/                 # CI job definitions and templates
├── .env.example                # Environment variable reference
├── flake.nix                   # Nix development environment
├── tofu/
│   ├── modules/                # Reusable OpenTofu modules
│   │   ├── hpa-deployment/     # HPA-enabled deployments
│   │   ├── cnpg-operator/      # CloudNativePG operator
│   │   ├── postgresql-cnpg/    # PostgreSQL cluster
│   │   ├── minio-operator/     # MinIO operator
│   │   ├── minio-tenant/       # MinIO tenant (S3 storage)
│   │   └── gitlab-runner/      # Self-hosted GitLab Runner
│   └── stacks/
│       └── attic/              # Main deployment stack
└── scripts/                    # Operational scripts
```

## Troubleshooting

```bash
# Health check
curl https://attic-cache.rigel.bates.edu/nix-cache-info

# View logs (requires cluster access)
kubectl logs -n attic-cache -l app.kubernetes.io/name=attic -f

# MinIO status
kubectl get tenant -n attic-cache
kubectl get pods -n attic-cache -l app.kubernetes.io/name=minio
```

## License

Internal Bates College use only.
