---
title: Create Your First Overlay
order: 5
---

# Create Your First Overlay

This guide walks you through creating a private overlay repository from scratch. By the end, you'll have a fully automated CI/CD pipeline that deploys Attic infrastructure to your Kubernetes cluster.

## What is an Overlay?

An overlay is a thin private repository that layers your organization-specific configuration on top of the public upstream modules. Think of it like CSS for infrastructure: upstream provides the structure, your overlay provides the values.

```
upstream (public)                    overlay (private)
  tofu/modules/gitlab-runner/          tofu/stacks/runners/beehive.tfvars
  tofu/modules/runner-dashboard/       tofu/stacks/runners/main.tf  (optional)
  tofu/stacks/attic/main.tf            config/organization.yaml
  tofu/stacks/gitlab-runners/main.tf   .gitlab-ci.yml
  app/                                 .env  (gitignored)
```

The overlay contains *only* your delta -- organization-specific config, secrets references, and CI pipeline. Upstream handles all the module logic.

**Why not just fork?** Forks diverge. With an overlay, you get upstream improvements (bug fixes, new runner types, dashboard features) by simply pulling the latest upstream commit. Your private configuration is never at risk of merge conflicts because it lives in separate files.

## Prerequisites

Before starting, you need:

- [ ] A Kubernetes cluster (1.28+) with kubectl access
- [ ] A GitLab group where your projects live
- [ ] A GitLab Personal Access Token (PAT) with `api` scope
- [ ] Nix with flakes enabled (see [Getting Started](../getting-started-guide.md))
- [ ] Git and a text editor

## Step 1: Clone Upstream

Clone the public upstream repo as a sibling directory to where your overlay will live:

```bash
git clone https://github.com/Jesssullivan/GloriousFlywheel.git ~/git/attic-iac
```

This directory must exist alongside your overlay -- the build system references it via relative path.

## Step 2: Create Your Overlay Repository

Create a new private repository on GitLab for your overlay, then clone it:

```bash
# Create the repo on GitLab (or use the GitLab UI)
# Then clone it as a sibling to attic-iac:
git clone git@gitlab.com:your-group/your-overlay.git ~/git/your-overlay
cd ~/git/your-overlay
```

Your directory layout should look like:

```
~/git/
  attic-iac/         # public upstream (from GitHub)
  your-overlay/      # private overlay (your GitLab repo)
```

## Step 3: Add the Bazel Overlay Files

The overlay system uses three files to merge upstream and private sources. Copy them from the templates below.

### `MODULE.bazel`

```python
"""Your Organization - Private overlay module."""

module(
    name = "your-overlay",
    version = "0.1.0",
)

# Upstream dependency
bazel_dep(name = "attic-iac", version = "0.1.0")

# Local dev: points to sibling upstream checkout
local_path_override(module_name = "attic-iac", path = "../../attic-iac")

# Core Bazel rules
bazel_dep(name = "bazel_skylib", version = "1.8.2")
bazel_dep(name = "rules_pkg", version = "1.1.0")

# Overlay extension: creates @attic_merged repo
overlay = use_extension("//build:extensions.bzl", "overlay")
overlay.configure(name = "attic_merged")
use_repo(overlay, "attic_merged")
```

> **Note:** The `local_path_override` path is relative to this file. Adjust if your directory layout differs from `~/git/attic-iac` and `~/git/your-overlay`.

### `build/overlay.bzl`

This file implements the symlink-merge repository rule. Copy it from the upstream repo:

```bash
mkdir -p build
cp ~/git/attic-iac/docs/infrastructure/templates/overlay.bzl build/overlay.bzl
```

Or copy from an existing overlay. The file is generic and works without modification.

#### Full overlay.bzl source

```python
"""Overlay repository rule for merging upstream and private sources.

Creates a repository that symlinks all files from an upstream Bazel module,
then overlays private files on top. Private files win on conflict.
"""

_EXCLUDE_DIRS = [".git", "bazel-", "node_modules", ".terraform", ".svelte-kit", "__pycache__"]
_EXCLUDE_FILES = ["MODULE.bazel", "MODULE.bazel.lock", "WORKSPACE", "WORKSPACE.bazel"]
_EXCLUDE_EXTENSIONS = [".tfstate", ".tfstate.backup"]

def _should_exclude(path):
    for d in _EXCLUDE_DIRS:
        if d in path.split("/"):
            return True
        for part in path.split("/"):
            if part.startswith("bazel-"):
                return True
    for f in _EXCLUDE_FILES:
        if path == f or path.endswith("/" + f):
            return True
    for ext in _EXCLUDE_EXTENSIONS:
        if path.endswith(ext):
            return True
    return False

def _find_files(ctx, root_path):
    result = ctx.execute(
        ["find", root_path, "-type", "f", "-not", "-path", "*/.git/*"],
        timeout = 30,
    )
    if result.return_code != 0:
        fail("Failed to list files in %s: %s" % (root_path, result.stderr))
    files = []
    for line in result.stdout.strip().split("\n"):
        if not line:
            continue
        rel = line
        if rel.startswith(root_path + "/"):
            rel = rel[len(root_path) + 1:]
        elif rel.startswith(root_path):
            rel = rel[len(root_path):]
        if rel and not _should_exclude(rel):
            files.append(rel)
    return files

def _ensure_parent_dirs(ctx, path):
    parent = "/".join(path.split("/")[:-1])
    if parent:
        ctx.execute(["mkdir", "-p", parent], timeout = 5)

def _overlay_repository_impl(ctx):
    upstream_path = str(ctx.path(ctx.attr.upstream_marker).dirname)
    overlay_path = str(ctx.path(ctx.attr.overlay_marker).dirname)
    ctx.watch_tree(upstream_path)
    ctx.watch_tree(overlay_path)

    upstream_files = _find_files(ctx, upstream_path)
    for f in upstream_files:
        _ensure_parent_dirs(ctx, f)
        ctx.symlink(ctx.path(upstream_path + "/" + f), f)

    overlay_files = _find_files(ctx, overlay_path)
    overlaid = []
    for f in overlay_files:
        _ensure_parent_dirs(ctx, f)
        target = ctx.path(f)
        if f in upstream_files:
            ctx.delete(target)
            overlaid.append(f)
        ctx.symlink(ctx.path(overlay_path + "/" + f), f)

    ctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])
filegroup(name = "all_files", srcs = glob(["**/*"], exclude = ["BUILD.bazel"]))
""")

overlay_repository = repository_rule(
    implementation = _overlay_repository_impl,
    attrs = {
        "upstream_marker": attr.label(mandatory = True),
        "overlay_marker": attr.label(mandatory = True),
    },
    local = True,
)
```

### `build/extensions.bzl`

```python
"""Module extension bridging MODULE.bazel tag declarations to overlay_repository."""

load("//build:overlay.bzl", "overlay_repository")

_configure = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "upstream_marker": attr.label(default = Label("@attic-iac//:MODULE.bazel")),
        "overlay_marker": attr.label(default = Label("//:MODULE.bazel")),
    },
)

def _overlay_extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for cfg in mod.tags.configure:
            overlay_repository(
                name = cfg.name,
                upstream_marker = cfg.upstream_marker,
                overlay_marker = cfg.overlay_marker,
            )

overlay = module_extension(
    implementation = _overlay_extension_impl,
    tag_classes = {"configure": _configure},
)
```

### `BUILD.bazel`

```python
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

package(default_visibility = ["//visibility:public"])

# Your org-specific filegroups
filegroup(name = "org_config", srcs = ["config/organization.yaml"])
filegroup(name = "org_tfvars", srcs = glob(["tofu/stacks/**/*.tfvars"]))
filegroup(name = "gitlab_ci", srcs = glob([".gitlab-ci.yml", ".gitlab/ci/**/*.yml"]))

# Aliases to upstream targets
alias(name = "validate_modules", actual = "@attic-iac//tofu/modules:all_validate")
alias(name = "app", actual = "@attic-iac//app:build")

# Deployment bundle
pkg_tar(
    name = "deployment_bundle",
    srcs = [":org_config", ":org_tfvars", ":gitlab_ci"],
    extension = "tar.gz",
    strip_prefix = ".",
)
```

## Step 4: Add Organization Configuration

### `config/organization.yaml`

```bash
mkdir -p config
```

Create `config/organization.yaml` with your cluster details:

```yaml
organization:
  name: your-org
  full_name: "Your Organization"
  group_path: your-gitlab-group

gitlab:
  url: https://gitlab.com
  project_id: "YOUR_OVERLAY_PROJECT_ID"
  agent_group: your-group/kubernetes/agents

clusters:
  - name: dev
    role: development
    domain: dev.example.com
    context: your-group/kubernetes/agents:dev

namespaces:
  attic:
    dev: attic-cache-dev
  runners:
    all: gitlab-runners

links:
  upstream_repo: "https://github.com/Jesssullivan/GloriousFlywheel"
  source_repo: "https://gitlab.com/your-group/your-overlay"
```

### `.env` (gitignored)

```bash
cp ~/git/attic-iac/.env.example .env
```

Set the `TF_HTTP_` credentials (see `.env.example`) to your GitLab PAT. This is used for the OpenTofu HTTP state backend.

### `.gitignore`

```
.env
*.tfstate
*.tfstate.backup
.terraform/
.svelte-kit/
kubeconfig-*
```

## Step 5: Add Stack Configuration (tfvars)

Each stack needs a tfvars file with your environment-specific values. Create them under `tofu/stacks/`:

### Cache Platform (attic stack)

```bash
mkdir -p tofu/stacks/attic
```

Create `tofu/stacks/attic/dev.tfvars` (provisions CNPG, PostgreSQL, MinIO, Attic API, GC, DNS):

```hcl
# Cluster access
cluster_context = "your-group/kubernetes/agents:dev"  # CI uses GitLab Agent path
namespace       = "attic-cache-dev"

# PostgreSQL
pg_instances    = 1
pg_storage      = "10Gi"
pg_storage_class = "default"  # Use your cluster's StorageClass

# MinIO
minio_storage   = "50Gi"

# Ingress
api_host = "nix-cache.dev.example.com"
```

### GitLab Runners

```bash
mkdir -p tofu/stacks/gitlab-runners
```

Create `tofu/stacks/gitlab-runners/dev.tfvars`:

```hcl
cluster_context = "your-group/kubernetes/agents:dev"
namespace       = "gitlab-runners"
gitlab_url      = "https://gitlab.com"

# Your GitLab group ID (Settings > General > Group ID)
gitlab_group_id = 12345678

# Runner types to deploy (disable what you don't need)
deploy_docker_runner = true
deploy_dind_runner   = true
deploy_rocky8_runner = false
deploy_rocky9_runner = false
deploy_nix_runner    = true

# Attic cache (for Nix runner)
attic_server   = "https://nix-cache.dev.example.com"
attic_cache    = "main"
nix_store_size = "20Gi"

# HPA
hpa_enabled = true
```

### Runner Dashboard

```bash
mkdir -p tofu/stacks/runner-dashboard
```

Create `tofu/stacks/runner-dashboard/dev.tfvars`:

```hcl
cluster_context  = "your-group/kubernetes/agents:dev"
namespace        = "runner-dashboard"
ingress_host     = "dashboard.dev.example.com"
runners_namespace = "gitlab-runners"
```

## Step 6: Self-Contained Stacks (Optional)

Some stacks need overlay-specific logic beyond what tfvars provide. For example, enrolling specific GitLab projects with dedicated runner registrations requires HCL resources that reference project IDs unique to your organization.

For these cases, create a self-contained `main.tf` in the overlay stack directory instead of using the upstream stack `.tf` files:

```bash
# Example: self-contained runner stack for project-level registrations
mkdir -p tofu/stacks/your-org-runners
```

See the [Bates runner enrollment docs](https://gitlab.com/bates-ils/people/jsullivan2/attic-cache/-/blob/main/docs/bates-runner-enrollment.md) for a worked example of project-level runner registration in a self-contained overlay stack.

## Step 7: Set Up CI Pipeline

Create `.gitlab-ci.yml` in your overlay root:

```yaml
# Your Organization - Overlay CI Pipeline
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

stages:
  - validate
  - plan
  - deploy

variables:
  UPSTREAM_REPO_URL: "https://github.com/Jesssullivan/GloriousFlywheel.git"
  UPSTREAM_REF: "main"
  TF_IN_AUTOMATION: "true"
  TF_INPUT: "false"

default:
  tags: [kubernetes]  # Target SaaS shared runners

# Clone upstream and symlink modules into overlay workspace
.setup_upstream: &setup_upstream
  - git clone --depth=1 --branch=$UPSTREAM_REF $UPSTREAM_REPO_URL /tmp/upstream
  # Symlink upstream modules into overlay
  - ln -sf /tmp/upstream/tofu/modules tofu/modules

# Base template for OpenTofu jobs
.tofu_base:
  image:
    name: ghcr.io/opentofu/opentofu:latest
    entrypoint: [""]
  variables:
    # CI job token authenticates to the HTTP state backend via TF_HTTP_* env vars
    TF_HTTP_USERNAME: gitlab-ci-token
  before_script:
    - *setup_upstream
    - |
      cd tofu/stacks/${STACK}
      tofu init \
        -backend-config="address=https://gitlab.com/api/v4/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}" \
        -backend-config="lock_address=https://gitlab.com/api/v4/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}/lock" \
        -backend-config="unlock_address=https://gitlab.com/api/v4/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}/lock"

# Attic Cache
plan:attic:
  extends: .tofu_base
  stage: plan
  variables:
    STACK: attic
    STATE_NAME: attic-dev
  script:
    - tofu plan -var-file=dev.tfvars -out=plan.tfplan
  artifacts:
    paths: [tofu/stacks/attic/plan.tfplan]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy:attic:
  extends: .tofu_base
  stage: deploy
  variables:
    STACK: attic
    STATE_NAME: attic-dev
  script:
    - tofu apply plan.tfplan
  needs: [plan:attic]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# Runners
plan:runners:
  extends: .tofu_base
  stage: plan
  variables:
    STACK: gitlab-runners
    STATE_NAME: runners-dev
  script:
    - tofu plan -var-file=dev.tfvars -var="gitlab_token=${GITLAB_TOKEN}" -out=plan.tfplan
  artifacts:
    paths: [tofu/stacks/gitlab-runners/plan.tfplan]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy:runners:
  extends: .tofu_base
  stage: deploy
  variables:
    STACK: gitlab-runners
    STATE_NAME: runners-dev
  script:
    - tofu apply plan.tfplan
  needs: [plan:runners]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

Adapt the template to include as many stacks as you deploy.

### Required CI/CD Variables

Set these in **Settings > CI/CD > Variables** on your GitLab overlay project:

| Variable | Scope | Description |
|----------|-------|-------------|
| `GITLAB_TOKEN` | All | PAT with `create_runner` scope (for automated runner token lifecycle) |
| `TF_VAR_gitlab_oauth_client_id` | All | OAuth app client ID (dashboard auth) |
| `TF_VAR_gitlab_oauth_client_secret` | All | OAuth app client secret (dashboard auth) |
| `TF_VAR_attic_token` | All | Attic cache auth token (Nix runners) |

## Step 8: Deploy

### First deployment (local)

For the initial deployment, run from your workstation:

```bash
cd ~/git/your-overlay
eval "$(grep '^TF_HTTP' .env)"  # Load state backend credentials

# Deploy in order: attic → runners → dashboard
for stack in attic gitlab-runners runner-dashboard; do
  cd tofu/stacks/$stack
  tofu init -backend-config="address=..." -backend-config="..."
  tofu plan -var-file=dev.tfvars -var="cluster_context=your-context" \
    -var="k8s_config_path=$HOME/git/your-overlay/kubeconfig"
  tofu apply
  cd ~/git/your-overlay
done
```

### Subsequent deployments (CI)

After the initial deployment, push to your overlay's `main` branch. The CI pipeline handles plan and apply automatically:

```bash
git add -A && git commit -m "feat: initial overlay deployment"
git push
```

## Step 9: Verify

```bash
# Pods running?
kubectl get pods -n attic-cache-dev
kubectl get pods -n gitlab-runners
kubectl get pods -n runner-dashboard

# Runners registered?
# Check: GitLab > Your Group > Settings > CI/CD > Runners
```

## Step 10: Enroll Projects

Once runners are deployed, project teams can start using them immediately by adding `tags:` to their `.gitlab-ci.yml`:

```yaml
default:
  tags: [docker]  # Route all jobs to the docker runner

build:container:
  tags: [dind]    # Docker-in-Docker for container builds

build:nix:
  tags: [nix]     # Nix builds with Attic cache
```

See [Self-Service Enrollment](../runners/self-service-enrollment.md) and [Project Onboarding](../runners/project-onboarding.md) for complete guides.

## Keeping Up with Upstream

To pull upstream improvements:

```bash
cd ~/git/attic-iac
git pull origin main
```

That's it. The overlay's `local_path_override` automatically picks up changes when you run `bazel build` or `tofu plan` locally. In CI, the pipeline clones the latest upstream on every run.

For pinned deployments (recommended for production), change `UPSTREAM_REF` in your `.gitlab-ci.yml` to a specific tag or commit SHA:

```yaml
variables:
  UPSTREAM_REF: "v1.2.0"  # or: "da8a495"
```

## Troubleshooting

### `local_path_override` path not found

The path in `MODULE.bazel` is relative to the overlay repo root. If your directories aren't siblings:

```
~/git/attic-iac/      # upstream
~/git/your-overlay/   # overlay -- MODULE.bazel says path = "../../attic-iac"
```

Adjust the `path` value to match your layout. Two `../` segments are needed because `local_path_override` resolves relative to the Bazel workspace root.

### OpenTofu state backend errors

GitLab's HTTP state backend occasionally returns 500. If a state becomes corrupted:

1. Try a different state name (append `-v2`)
2. Re-initialize with the new state name
3. Import existing resources if needed

### Runners not visible in project

Runners registered at a GitLab group only propagate *downward* in the hierarchy. If your project is in a sibling subgroup, you need project-level registrations. See the [enrollment docs](../runners/self-service-enrollment.md) for details.

### CI pipeline can't clone upstream

The CI pipeline clones upstream from GitHub over HTTPS. If your GitLab runners are on a restricted network (no GitHub access), you have two options:

1. Use SaaS shared runners for CI (set `tags: [kubernetes]` on pipeline jobs)
2. Mirror the upstream repo to your GitLab instance and change `UPSTREAM_REPO_URL`

## Directory Structure Reference

A complete overlay repository looks like this:

```
your-overlay/
  MODULE.bazel              # Declares upstream dependency
  BUILD.bazel               # Build targets and aliases
  .gitlab-ci.yml            # CI/CD pipeline
  .gitignore                # Exclude .env, tfstate, etc.
  .env                      # Secrets (gitignored)
  build/
    overlay.bzl             # Symlink-merge repository rule
    extensions.bzl          # Module extension bridge
  config/
    organization.yaml       # Organization identity and cluster config
  tofu/
    stacks/
      attic/
        dev.tfvars          # Attic cache config per environment
      gitlab-runners/
        dev.tfvars          # Runner config per environment
        main.tf             # (optional) Self-contained stack for project enrollments
      runner-dashboard/
        dev.tfvars          # Dashboard config per environment
  docs/                     # (optional) Org-specific documentation
```

## Related Documentation

- [Overlay System](../architecture/overlay-system.md) -- deep dive on the symlink-merge mechanics
- [Bzlmod Topology](../architecture/bzlmod-topology.md) -- how Bazel modules connect
- [Multi-Repo Layout](../architecture/multi-repo-layout.md) -- repository hosting and CI flow
- [Quick Start](./quick-start.md) -- direct deployment guide
- [Customization Guide](./customization-guide.md) -- full `organization.yaml` reference
