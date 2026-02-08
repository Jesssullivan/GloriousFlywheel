---
title: Overlay Pipelines
order: 10
---

# Overlay Pipelines

Overlay repositories (such as `attic-cache-bates` or `tinyland-infra`) extend the
upstream pipeline to deploy site-specific infrastructure. Each overlay maintains its
own `.gitlab-ci.yml` that pulls upstream code at a pinned ref and merges it with
local configuration.

## How It Works

### Upstream Clone

The overlay pipeline begins by cloning the upstream repository from GitHub:

```yaml
variables:
  UPSTREAM_REPO_URL: "https://github.com/Jesssullivan/attic-iac.git"
  UPSTREAM_REF: "main"
```

The `UPSTREAM_REF` variable controls which commit, tag, or branch of upstream
code is used. Pinning to a tag (e.g., `v1.2.0`) is recommended for production
overlays; using `main` tracks the latest upstream changes.

### Symlink Merge

After cloning, the pipeline symlinks upstream modules and `.tf` files into the
overlay stack directories. This gives each stack access to:

- Shared module definitions from `tofu/modules/`
- Upstream `.tf` root files (providers, backends, data sources)
- Overlay-specific `.tfvars` files that override upstream defaults

The result is a merged working directory where overlay configuration takes
precedence over upstream defaults on conflict.

### Stack-Specific tfvars

Each overlay defines its own variable files for each target environment:

- `beehive.tfvars` -- Bates development cluster
- `tinyland.tfvars` -- Tinyland production cluster

These files set cluster contexts, namespaces, domains, resource limits, and
any other site-specific values.

### Extra Stages and Jobs

Overlays can add stages or jobs beyond the upstream pipeline. Common additions:

- Organization config validation (checks overlay-specific `organization.yaml`)
- Additional deployment targets not present in upstream
- Site-specific integration tests or smoke tests

## CI Variables

The following CI/CD variables must be configured in the overlay project settings:

| Variable | Purpose |
|----------|---------|
| `UPSTREAM_REPO_URL` | GitHub URL for the upstream repository |
| `UPSTREAM_REF` | Git ref (branch, tag, or SHA) to clone from upstream |
| `TF_HTTP_PASSWORD` | GitLab PAT for the tofu HTTP state backend |
| `TF_VAR_gitlab_token` | GitLab token passed to the tofu GitLab provider |
| `TF_VAR_gitlab_oauth_client_id` | OAuth application ID for dashboard auth |
| `TF_VAR_gitlab_oauth_client_secret` | OAuth application secret |

Cluster context variables are set per environment, either as CI variables or
within the `.tfvars` files.

## State Storage

Each overlay project stores its own tofu state in the GitLab HTTP backend. State
is scoped per project and per stack:

- State name format: `{stack}-{environment}` (e.g., `attic-beehive`, `runners-beehive`)
- Backend project ID: the GitLab project ID of the overlay repository
- Authentication: via `TF_HTTP_PASSWORD`

This ensures that each overlay maintains independent state, even when multiple
overlays deploy the same upstream modules.

## Related

- [Pipeline Overview](./pipeline-overview.md) -- upstream pipeline stages
- [Deployment Flow](./deployment-flow.md) -- commit-to-production flow
- [Environment Variables](../reference/environment-variables.md) -- full variable reference
