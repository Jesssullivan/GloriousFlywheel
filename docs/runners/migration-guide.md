# Migration Guide: Manual Tokens to Self-Service Runners

How to migrate from manually-managed runner registration tokens to the
automated self-service model using `gitlab_user_runner`.

## Before: Manual Token Management

The legacy setup required operators to:

1. Generate runner registration tokens in the GitLab UI.
2. Set `TF_VAR_*_runner_token` environment variables per runner type:
   ```
   TF_VAR_docker_runner_token=glrt-...
   TF_VAR_dind_runner_token=glrt-...
   TF_VAR_rocky8_runner_token=glrt-...
   TF_VAR_rocky9_runner_token=glrt-...
   TF_VAR_nix_runner_token=glrt-...
   ```
3. Rotate tokens manually when they expired or were revoked.
4. Use `ci-templates/` with `extends:` to reference shared job definitions.

**Problems**: token sprawl, manual rotation, no audit trail, tight coupling
between templates and downstream projects.

## After: Automated Self-Service

The new model uses the `gitlab_user_runner` Terraform resource to register
runners at the group level automatically. Tokens are managed by OpenTofu and
stored in Kubernetes secrets.

Downstream projects use `include: component:` syntax instead of `extends:`.

## Migration Steps

### Step 1: Set the GitLab Group ID

In your runner stack tfvars (e.g., `tofu/stacks/runners/{environment}.tfvars`):

```hcl
gitlab_group_id = 12345678
```

When `gitlab_group_id` is set to a non-zero value, the module creates
`gitlab_user_runner` resources and manages tokens automatically.

### Step 2: Provide a GitLab Token

Set a GitLab personal access token (or group token) with the `create_runner`
scope:

```bash
export TF_VAR_gitlab_token=glpat-XXXX
```

This token is used only by OpenTofu to create runner registrations. It is
**not** the runner authentication token.

### Step 3: Apply the Stack

```bash
just plan {environment}
just apply {environment}
```

OpenTofu will:

- Create `gitlab_user_runner` resources for each runner type.
- Store the generated authentication tokens in Kubernetes secrets.
- Configure the runner deployments to read tokens from secrets.

### Step 4: Remove Legacy Token Variables

Once the automated runners are healthy, remove the old `TF_VAR_*_runner_token`
variables from your CI/CD settings and any local `.envrc` files.

### Step 5: Migrate CI Templates

See the CI template migration section below.

## Backward Compatibility

When `gitlab_group_id = 0` (the default), the module falls back to manual
token management. The `TF_VAR_*_runner_token` variables are used as before.

This means you can migrate clusters independently. For example, migrate
`dev-cluster` first while `prod-cluster` continues using manual
tokens.

## CI Template Migration

### Before: ci-templates with extends

```yaml
# Old pattern
include:
  - project: "{org}/projects/iac/attic-cache"
    file: "ci-templates/docker.yml"
    ref: main

build:
  extends: .docker-job
  script:
    - make build
```

### After: CI/CD Components

```yaml
# New pattern
include:
  - component: $CI_SERVER_FQDN/{org}/projects/iac/attic-cache/docker-job@main
    inputs:
      stage: build
      script: make build
```

### Key Differences

| Aspect          | ci-templates (legacy)   | Components (new)           |
| --------------- | ----------------------- | -------------------------- |
| Syntax          | `include: project/file` | `include: component:`      |
| Customization   | `extends:` + overrides  | `inputs:` parameters       |
| Versioning      | `ref:` on include       | `@ref` suffix on component |
| Validation      | None                    | Input schema validation    |
| Discoverability | Read the YAML           | GitLab CI/CD catalog       |

### Migration Mapping

| Legacy Template                 | Component      |
| ------------------------------- | -------------- |
| `ci-templates/docker.yml`       | `docker-job`   |
| `ci-templates/dind.yml`         | `dind-job`     |
| `ci-templates/rocky8.yml`       | `rocky8-job`   |
| `ci-templates/rocky9.yml`       | `rocky9-job`   |
| `ci-templates/nix.yml`          | `nix-job`      |
| `ci-templates/docker-build.yml` | `docker-build` |
| `ci-templates/k8s-deploy.yml`   | `k8s-deploy`   |

## Deprecation Timeline

| Date      | Milestone                                          |
| --------- | -------------------------------------------------- |
| Now       | Components available, ci-templates still supported |
| +30 days  | ci-templates emit deprecation warnings in job logs |
| +90 days  | ci-templates frozen (no new features or bug fixes) |
| +180 days | ci-templates removed from main branch              |

Projects should migrate to components within the 90-day window. After removal,
pipelines referencing `ci-templates/` will fail.
