---
title: Justfile Commands
order: 30
---

# Justfile Commands

The project Justfile provides recipes for common development, build, and
deployment tasks. Run `just --list` to see all available recipes or
`just <recipe> --help` for usage details.

## Proxy

Recipes for managing the SOCKS5 proxy used to reach on-premise clusters from
off-site.

| Recipe | Description |
|--------|-------------|
| `just proxy-up` | Start the SOCKS5 proxy via SSH tunnel to the on-premise jump host |
| `just proxy-down` | Stop the SOCKS5 proxy tunnel |
| `just proxy-status` | Check whether the proxy tunnel is running |
| `just bk <args>` | Run kubectl through the SOCKS proxy (shorthand for proxied kubectl) |
| `just bcurl <args>` | Run curl through the SOCKS proxy |

## Development

General development workflow recipes.

| Recipe | Description |
|--------|-------------|
| `just dev` | Start all development servers (app + docs) |
| `just check` | Run quick checks (lint, format, type check) |
| `just check-full` | Run full validation suite (lint, format, type check, tests, tofu validate) |
| `just info` | Print project info (versions, paths, git status) |

## Nix

Recipes for Nix-based builds and maintenance.

| Recipe | Description |
|--------|-------------|
| `just nix-build` | Build the project with Nix |
| `just nix-build-container` | Build the OCI container image via nix2container |
| `just nix-check` | Run `nix flake check` |
| `just nix-update` | Update flake inputs |

## OpenTofu

Infrastructure-as-code recipes for planning and applying changes.

| Recipe | Description |
|--------|-------------|
| `just tofu-init` | Initialize tofu for all stacks |
| `just tofu-plan` | Run tofu plan for all stacks |
| `just tofu-apply` | Run tofu apply for all stacks |
| `just tofu-deploy` | Full deploy cycle: init, plan, apply |
| `just tofu-validate-all` | Run tofu validate against every module in `tofu/modules/` |

## Bazel

Build system recipes for the Bzlmod-based build.

| Recipe | Description |
|--------|-------------|
| `just bazel-build` | Build all targets (`bazel build //...`) |
| `just bazel-test` | Run all tests (`bazel test //...`) |
| `just bazel-clean` | Clean Bazel build outputs |

## Kubernetes

Cluster inspection and debugging recipes. All commands route through the proxy
when `HTTPS_PROXY` is set.

| Recipe | Description |
|--------|-------------|
| `just k8s-pods` | List pods in the target namespace |
| `just k8s-logs` | Tail logs from a pod |
| `just k8s-describe` | Describe a Kubernetes resource |
| `just k8s-events` | Show recent events in the namespace |
| `just k8s-forward` | Port-forward to a pod or service |

## App (Runner Dashboard)

Recipes for the SvelteKit runner-dashboard application.

| Recipe | Description |
|--------|-------------|
| `just app-install` | Install app dependencies with pnpm |
| `just app-dev` | Start the SvelteKit dev server |
| `just app-build` | Production build via adapter-node |
| `just app-test` | Run the test suite (Vitest) |
| `just app-check` | Run svelte-check (type checking) |

## Runners

Recipes specific to the GitLab Runner infrastructure stack.

| Recipe | Description |
|--------|-------------|
| `just runners-init` | Initialize tofu for the runners stack |
| `just runners-plan` | Plan changes to the runners stack |
| `just runners-apply` | Apply changes to the runners stack |

## Attic

Recipes for the Attic binary cache stack.

| Recipe | Description |
|--------|-------------|
| `just attic-init` | Initialize tofu for the attic stack |
| `just attic-plan` | Plan changes to the attic stack |
| `just attic-apply` | Apply changes to the attic stack |
| `just attic-status` | Show current attic deployment status |
| `just attic-health` | Run health check against the attic server endpoint |

## Docs

Recipes for the documentation site.

| Recipe | Description |
|--------|-------------|
| `just docs-dev` | Start the documentation site dev server |
| `just docs-build` | Build the documentation site for deployment |

## TeX

Recipes for building the research document.

| Recipe | Description |
|--------|-------------|
| `just tex` | Compile the TeX research document to PDF |
| `just tex-clean` | Remove TeX build artifacts |
| `just tex-watch` | Watch for changes and recompile automatically |

## Related

- [Environment Variables](./environment-variables.md) -- variables consumed by these recipes
- [Configuration Reference](./config-reference.md) -- organization.yaml used by tofu recipes
- [Pipeline Overview](../ci-cd/pipeline-overview.md) -- CI equivalents of local recipes
