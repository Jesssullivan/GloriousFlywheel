# Quick Start Guide

Get up and running with self-hosted Attic binary cache and GitLab runners in under 30 minutes.

## Prerequisites

Before you begin, ensure you have:

- **Kubernetes cluster** (1.24+)

  - kubectl access with cluster-admin permissions
  - At least 3 nodes recommended for HA
  - Storage class that supports dynamic provisioning

- **GitLab** (GitLab.com or self-hosted 15.0+)

  - GitLab group for your organization
  - GitLab Kubernetes Agent configured (see [Agent Setup](#gitlab-agent-setup))
  - Personal Access Token with `api` scope

- **Local tools**:

  - `kubectl` - Kubernetes CLI
  - `yq` - YAML processor (`brew install yq`)
  - `just` - Task runner (`brew install just`)
  - `opentofu` or `terraform` - Infrastructure as Code
  - `direnv` (optional but recommended)

- **DNS**:
  - Wildcard DNS or ability to create A records for `*.your-domain.com`
  - Ingress controller in your cluster (traefik, nginx, etc.)
  - TLS certificates (Let's Encrypt via cert-manager recommended)

## Step 1: Clone and Customize

```bash
# Clone the repository
git clone https://github.com/Jesssullivan/attic-iac.git
cd attic-iac

# Create your organization config from template
cp config/organization.example.yaml config/organization.yaml

# Edit with your organization details
$EDITOR config/organization.yaml
```

### Required Configuration

Update these fields in `config/organization.yaml`:

```yaml
organization:
  name: myorg # Your org identifier (lowercase, no spaces)
  full_name: "My Organization" # Display name
  group_path: mygroup # GitLab group path

gitlab:
  url: https://gitlab.com
  project_id: "YOUR_PROJECT_ID" # GitLab project for Terraform state
  agent_group: mygroup/kubernetes/agents # Path to K8s agent config

clusters:
  - name: dev # Cluster identifier
    role: development
    domain: dev.example.com # Base domain for ingress
    context: mygroup/kubernetes/agents:dev # GitLab Agent context

namespaces:
  runners:
    all: gitlab-runners # Namespace for runners
```

## Step 2: GitLab Agent Setup

### 2.1 Create Agent Configuration

In your GitLab group, create a project for Kubernetes Agent configuration:

```bash
# Example: gitlab.com/mygroup/kubernetes/agents
```

Create `.gitlab/agents/dev/config.yaml`:

```yaml
ci_access:
  groups:
    - id: mygroup
      default_namespace: gitlab-runners

user_access:
  access_as:
    agent: {}
  projects:
    - id: mygroup/*
```

### 2.2 Register Agent

```bash
# Get agent token from GitLab UI:
# Settings > Kubernetes > Connect a cluster

# Install agent in your cluster
helm repo add gitlab https://charts.gitlab.io
helm repo update

helm upgrade --install dev gitlab/gitlab-agent \
  --namespace gitlab-agent-dev \
  --create-namespace \
  --set config.token=YOUR_AGENT_TOKEN \
  --set config.kasAddress=wss://kas.gitlab.com
```

### 2.3 Verify Agent Connection

Check agent status in GitLab UI: `Settings > Kubernetes > View agent`

## Step 3: Configure Secrets

```bash
# Create .env for local development
cp .env.example .env
```

Edit `.env` and add your GitLab Personal Access Token:

```bash
TF_HTTP_PASSWORD=glpat-your-token-here
```

Allow direnv to load environment:

```bash
direnv allow
```

## Step 4: Customize Deployment

Create environment-specific tfvars:

```bash
# For development cluster
cp tofu/stacks/attic/beehive.tfvars tofu/stacks/attic/dev.tfvars
$EDITOR tofu/stacks/attic/dev.tfvars
```

Key settings to customize:

```hcl
# Cluster authentication
cluster_context    = "mygroup/kubernetes/agents:dev"
ingress_domain     = "dev.example.com"
namespace          = "attic-cache-dev"

# Database (start with single instance)
pg_instances       = 1
pg_storage_size    = "10Gi"

# Storage (MinIO for simplicity, or use external S3)
use_minio          = true
minio_volume_size  = "20Gi"

# API scaling (start small)
api_min_replicas   = 1
api_max_replicas   = 3
```

## Step 5: Deploy Attic Cache

```bash
# Initialize Terraform backend
cd tofu/stacks/attic
tofu init

# Plan deployment
ENV=dev just tofu-plan attic

# Review the plan carefully, then apply
ENV=dev just tofu-apply attic
```

**Expected resources**: ~25 Kubernetes resources including:

- Namespace
- PostgreSQL cluster (CNPG)
- MinIO tenant (or external S3 config)
- Attic API deployment + HPA
- Ingress with TLS
- Service monitors (if Prometheus enabled)

## Step 6: Verify Deployment

### 6.1 Check Health

```bash
# Check all pods are running
kubectl get pods -n attic-cache-dev

# Check attic API health
curl https://attic-cache.dev.example.com/nix-cache-info

# Expected output:
# StoreDir: /nix/store
# WantMassQuery: 1
# Priority: 40
```

### 6.2 Test Cache Push

```bash
# Configure attic CLI locally
export ATTIC_SERVER=https://attic-cache.dev.example.com
export ATTIC_CACHE=main

# Test push (requires nix and attic CLI)
echo "test" | nix-store --add --name test
attic push main $(nix-store -q --outputs $(nix-instantiate --eval -E 'builtins.currentSystem'))
```

## Step 7: Deploy GitLab Runners (Optional)

```bash
# Create runner tfvars
cp tofu/stacks/bates-ils-runners/beehive.tfvars tofu/stacks/bates-ils-runners/dev.tfvars
$EDITOR tofu/stacks/bates-ils-runners/dev.tfvars

# Update namespace and cluster
namespace = "gitlab-runners"
cluster_context = "mygroup/kubernetes/agents:dev"

# Deploy runners
cd tofu/stacks/bates-ils-runners
ENV=dev just tofu-plan
ENV=dev just tofu-apply
```

## Step 8: Integrate with CI/CD

### 8.1 Configure Nix Projects

Add to your project's `.gitlab-ci.yml`:

```yaml
include:
  - component: gitlab.com/mygroup/attic-iac/nix-build@main
    inputs:
      attic_cache: main
      attic_server: https://attic-cache.dev.example.com
```

### 8.2 Configure Docker Projects

```yaml
include:
  - component: gitlab.com/mygroup/attic-iac/docker-build@main
```

## Next Steps

- **Scale up**: Increase replicas and resources as usage grows
- **Add monitoring**: Deploy runner dashboard (see [Runner Dashboard](runners/README.md))
- **Enable HA**: Configure 3-node PostgreSQL and distributed MinIO (see [Customization Guide](customization-guide.md))
- **Production deploy**: Repeat for staging/prod clusters
- **Optimize**: Tune HPA settings based on observed usage

## Troubleshooting

### Pods stuck in Pending

Check storage class and PVC status:

```bash
kubectl get pvc -n attic-cache-dev
kubectl describe pvc <pvc-name> -n attic-cache-dev
```

### Ingress not accessible

Check ingress and certificate:

```bash
kubectl get ingress -n attic-cache-dev
kubectl get certificate -n attic-cache-dev
kubectl describe certificate <cert-name> -n attic-cache-dev
```

### PostgreSQL init failures

Check CNPG operator logs:

```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

### More help

See comprehensive troubleshooting in [docs/runners/troubleshooting.md](runners/troubleshooting.md)

## Support

- Issues: https://github.com/Jesssullivan/attic-iac/issues
- Discussions: https://github.com/Jesssullivan/attic-iac/discussions
