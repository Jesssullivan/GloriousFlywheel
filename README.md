# Attic Cache - Bates ILS Nix Binary Cache

Self-hosted Nix binary cache for Bates College infrastructure, deployed to internal Kubernetes clusters using GitLab CI/CD and the GitLab Kubernetes Agent.

## Overview

Attic is a self-hosted Nix binary cache that stores pre-built Nix derivations, dramatically speeding up builds across CI/CD pipelines and development environments.

### Key Features

- **Auth-free operation** - Public read/write on internal Bates network
- **Greedy build pattern** - Immediate cache pushes for resumable builds
- **Multi-environment** - Development (beehive), staging/production (rigel)
- **GitLab Kubernetes Agent** - No kubeconfig management required
- **MinIO integration** - Self-managed S3-compatible storage (default)

## Architecture

```
                      GitLab CI/CD
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │  nix:build   │  │ tofu:plan    │  │   deploy     │
  │  (greedy)    │  │              │  │              │
  └──────────────┘  └──────────────┘  └──────────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │ GitLab K8s Agent
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
  │   beehive     │   │    rigel      │   │    rigel      │
  │   (review)    │   │  (staging)    │   │ (production)  │
  │ *.beehive.    │   │ *.rigel.      │   │ *.rigel.      │
  │   bates.edu   │   │   bates.edu   │   │   bates.edu   │
  └───────────────┘   └───────────────┘   └───────────────┘
```

## Clusters

### Beehive (Development/Review)

- **Purpose**: Merge request reviews, development testing
- **GitLab Agent**: `bates-ils/projects/kubernetes/gitlab-agents:beehive`
- **Domain**: `*.beehive.bates.edu`
- **Resources**: Minimal (single replica, reduced limits)

### Rigel (Staging/Production)

- **Purpose**: Staging validation, production workloads
- **GitLab Agent**: `bates-ils/projects/kubernetes/gitlab-agents:rigel`
- **Domain**: `*.rigel.bates.edu`
- **Resources**: HA configuration (multiple replicas, PostgreSQL cluster)

## Deployment

Deployments are fully automated via GitLab CI/CD:

| Branch/Tag  | Environment | Cluster | Auto-deploy |
| ----------- | ----------- | ------- | ----------- |
| Feature/MR  | review      | beehive | Yes         |
| main        | staging     | rigel   | Yes         |
| v*.*.\* tag | production  | rigel   | Manual      |

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

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# GitLab Kubernetes Agent Context
KUBE_CONTEXT=bates-ils/projects/kubernetes/gitlab-agents:beehive

# Namespace configuration
NAMESPACE=attic-cache
KUBE_INGRESS_BASE_DOMAIN=beehive.bates.edu

# Attic Configuration
ATTIC_SERVER=https://attic-cache.beehive.bates.edu
ATTIC_CACHE=main
```

### Storage Options

#### MinIO (Default)

Both beehive and rigel use MinIO for S3-compatible storage by default (`use_minio=true`). This provides:

- Self-managed storage within the cluster
- No external S3 credentials required
- Automatic bucket lifecycle management
- PostgreSQL backups to MinIO

| Environment   | Mode            | Drives  | Total Storage |
| ------------- | --------------- | ------- | ------------- |
| beehive (dev) | Standalone      | 1×10Gi  | 10Gi          |
| rigel (prod)  | Distributed 4×4 | 16×50Gi | 800Gi raw     |

#### External S3 (Optional)

To use external S3 instead of MinIO, set `use_minio=false` in your tfvars and configure these CI/CD variables:

| Variable               | Description     | Required                   |
| ---------------------- | --------------- | -------------------------- |
| `S3_ENDPOINT`          | S3 endpoint URL | Yes (when use_minio=false) |
| `S3_ACCESS_KEY_ID`     | S3 access key   | Yes (masked)               |
| `S3_SECRET_ACCESS_KEY` | S3 secret key   | Yes (masked)               |
| `S3_BUCKET_NAME`       | S3 bucket name  | Yes                        |

## Using the Cache

### Configure Nix to Use the Cache

Add to your `~/.config/nix/nix.conf` or project's `flake.nix`:

```nix
# nix.conf
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

The greedy build pattern automatically pushes artifacts:

```yaml
nix:build:
  script:
    - nix build .#mypackage --out-link result
    - nix run .#attic -- push main result || echo "Cache push (non-blocking)"
```

## Development

### Prerequisites

- Nix with flakes enabled
- direnv (recommended)

### Local Setup

```bash
# Enter development shell
direnv allow
# or
nix develop

# Validate configuration
cd tofu/stacks/attic
tofu init -backend=false
tofu validate
```

### Project Structure

```
.
├── .gitlab-ci.yml          # CI/CD pipeline (Bates patterns)
├── .env.example            # Environment variable template
├── flake.nix               # Nix development environment
├── docs/
│   ├── greedy-build-pattern.md  # Build caching documentation
│   └── k8s-reference/           # Reference Kubernetes manifests
├── tofu/
│   ├── modules/            # Reusable OpenTofu modules
│   │   ├── cnpg-operator/  # CloudNativePG operator
│   │   ├── hpa-deployment/ # HPA-enabled deployments
│   │   ├── minio-operator/ # MinIO operator
│   │   ├── minio-tenant/   # MinIO tenant (S3 storage)
│   │   └── postgresql-cnpg/# PostgreSQL cluster
│   └── stacks/
│       └── attic/
│           ├── main.tf         # Main configuration
│           ├── variables.tf    # Variable definitions
│           ├── beehive.tfvars  # Dev cluster config
│           └── rigel.tfvars    # Prod cluster config
└── scripts/                # Operational scripts
```

## Greedy Build Pattern

This repository implements the "greedy build → immediately push" pattern for Nix caching:

1. **Build jobs use `needs: []`** - Start immediately, don't wait for validation
2. **Cache push is non-blocking** - Failures logged but don't fail the job
3. **Artifacts preserved** - GitLab keeps build artifacts even on downstream failures
4. **Resumable builds** - Subsequent pipelines leverage cached derivations

See [docs/greedy-build-pattern.md](docs/greedy-build-pattern.md) for details.

## Troubleshooting

### Health Check

```bash
# Check cache status
curl https://attic-cache.rigel.bates.edu/nix-cache-info

# Expected output:
# StoreDir: /nix/store
# WantMassQuery: 1
# Priority: 30
```

### View Logs

```bash
# Via kubectl (requires cluster access)
kubectl logs -n attic-cache -l app.kubernetes.io/name=attic -f
```

### MinIO Status

```bash
# Check MinIO tenant status
kubectl get tenant -n attic-cache

# Check MinIO pods
kubectl get pods -n attic-cache -l app.kubernetes.io/name=minio
```

### Common Issues

**Cache push fails silently**: Check S3 credentials (or MinIO status) and bucket permissions.

**Slow builds**: Verify the cache is being used with `--print-build-logs`.

**Ingress not working**: Check cert-manager issuer and DNS propagation.

**MinIO not ready**: Check operator logs in `minio-operator` namespace.

## License

Internal Bates College use only.
