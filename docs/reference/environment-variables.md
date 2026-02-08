---
title: Environment Variables
order: 20
---

# Environment Variables

This document lists all environment variables used across the attic-iac project,
including CI/CD pipelines, local development, and runtime configuration.

## OpenTofu Backend and Provider

| Variable | Required | Description |
|----------|----------|-------------|
| `TF_HTTP_PASSWORD` | Yes | GitLab Personal Access Token for the tofu HTTP state backend. Must have `api` scope on the project that stores state. |
| `TF_VAR_gitlab_token` | Yes | GitLab token passed to the tofu GitLab provider for managing GitLab resources (runner registrations, project settings). |

## OAuth (Runner Dashboard)

| Variable | Required | Description |
|----------|----------|-------------|
| `TF_VAR_gitlab_oauth_client_id` | For dashboard | OAuth2 application ID for GitLab authentication in the runner dashboard. |
| `TF_VAR_gitlab_oauth_client_secret` | For dashboard | OAuth2 application secret. Must be kept confidential. |

## Attic Cache

| Variable | Required | Description |
|----------|----------|-------------|
| `ATTIC_SERVER` | On nix runners | URL of the Attic binary cache server (e.g., `https://attic.apps.example.com`). Set as a runner environment variable on nix-type runners. |
| `ATTIC_CACHE` | On nix runners | Name of the Attic cache to push/pull from (e.g., `main`). |

## SvelteKit Runtime (Runner Dashboard)

The runner-dashboard application reads environment variables with the
`DASHBOARD_` prefix at runtime (SvelteKit `$env/dynamic/private`).

| Variable | Required | Description |
|----------|----------|-------------|
| `DASHBOARD_GITLAB_API_URL` | Yes | Base URL for the GitLab API (e.g., `https://gitlab.com/api/v4`). |
| `DASHBOARD_GITLAB_TOKEN` | Yes | GitLab token for the dashboard to query runner and pipeline status. |
| `DASHBOARD_GITLAB_GROUP_ID` | Yes | GitLab group ID whose runners are displayed. |

## Documentation Site

| Variable | Required | Description |
|----------|----------|-------------|
| `DOCS_BASE_PATH` | No | Base URL path for the documentation site when deployed under a subpath (e.g., `/attic-iac/docs`). Defaults to `/`. |

## Network and Proxy

| Variable | Required | Description |
|----------|----------|-------------|
| `HTTPS_PROXY` | Off-site | SOCKS5 proxy URL for accessing on-premise Kubernetes clusters remotely (e.g., `socks5h://localhost:1080`). Required when running tofu or kubectl against clusters behind a firewall. |

## CI/CD Pipeline

These variables are typically set in the GitLab project CI/CD settings, not
locally.

| Variable | Required | Description |
|----------|----------|-------------|
| `UPSTREAM_REPO_URL` | Overlay only | GitHub URL of the upstream attic-iac repository. Used by overlay pipelines to clone upstream code. |
| `UPSTREAM_REF` | Overlay only | Git ref (branch, tag, or SHA) to check out from the upstream repository. Defaults to `main`. |
| `GITLAB_TOKEN` | CI only | Token used by CI jobs for GitLab API calls (runner registration, status checks). Distinct from `TF_VAR_gitlab_token` in scope. |
| `CI_ENVIRONMENT_NAME` | CI only | Set by GitLab CI; used to select the correct `.tfvars` file and state key. |

## Local Development

These are not environment variables per se, but local configuration that
supplements the variables above.

| Item | Description |
|------|-------------|
| `kubeconfig-{environment}` | Kubeconfig file (gitignored) for direct cluster access. Path passed via `TF_VAR_k8s_config_path`. |
| `~/.ssh/gitlab-key` | SSH key for your GitLab account. |
| `.env` | Local environment file (gitignored) containing `TF_HTTP_PASSWORD` and other secrets. Never committed. |

## Related

- [Configuration Reference](./config-reference.md) -- organization.yaml schema
- [Overlay Pipelines](../ci-cd/overlay-pipelines.md) -- CI variable usage in overlays
- [Justfile Commands](./justfile-commands.md) -- recipes that consume these variables
