# ARC Runners Stack
#
# Deploys GitHub Actions Runner Controller (ARC) and runner scale sets
# to Kubernetes. Provides `runs-on: tinyland-nix`, `tinyland-docker`,
# and `tinyland-dind` labels for GitHub Actions workflows.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "kubernetes" {
  config_path    = var.k8s_config_path != "" ? var.k8s_config_path : null
  config_context = var.cluster_context
}

provider "helm" {
  kubernetes {
    config_path    = var.k8s_config_path != "" ? var.k8s_config_path : null
    config_context = var.cluster_context
  }
}

# =============================================================================
# Runner Namespace (shared by all scale sets)
# =============================================================================

resource "kubernetes_namespace_v1" "arc_runners" {
  count = var.create_runner_namespace ? 1 : 0

  metadata {
    name = var.runner_namespace
    labels = {
      "app.kubernetes.io/name"       = "arc-runners"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/component"  = "runner-pool"
    }
  }
}

# =============================================================================
# ARC Controller
# =============================================================================

module "arc_controller" {
  source = "../../modules/arc-controller"

  namespace          = var.controller_namespace
  create_namespace   = var.create_controller_namespace
  chart_version      = var.controller_chart_version
  image_pull_secrets = local.ghcr_pull_secrets
}

# =============================================================================
# Nix Runner - runs-on: tinyland-nix
# =============================================================================

module "gh_nix" {
  source = "../../modules/arc-runner"

  runner_name          = var.nix_runner_name
  runner_label         = "tinyland-nix"
  runner_type          = "nix"
  namespace            = var.runner_namespace
  controller_namespace = var.controller_namespace
  github_config_url    = var.github_config_url
  github_config_secret = var.github_config_secret

  min_runners = var.nix_min_runners
  max_runners = var.nix_max_runners

  cpu_request    = var.nix_cpu_request
  memory_request = var.nix_memory_request
  cpu_limit      = var.nix_cpu_limit
  memory_limit   = var.nix_memory_limit

  attic_server         = var.attic_server
  attic_cache          = var.attic_cache
  bazel_cache_endpoint = var.bazel_cache_endpoint

  image_pull_secrets = local.ghcr_pull_secrets

  depends_on = [module.arc_controller, kubernetes_namespace_v1.arc_runners]
}

# =============================================================================
# Docker Runner - runs-on: tinyland-docker
# =============================================================================

module "gh_docker" {
  source = "../../modules/arc-runner"
  count  = var.deploy_docker_runner ? 1 : 0

  runner_name          = var.docker_runner_name
  runner_label         = "tinyland-docker"
  runner_type          = "docker"
  namespace            = var.runner_namespace
  controller_namespace = var.controller_namespace
  github_config_url    = var.github_config_url
  github_config_secret = var.github_config_secret

  min_runners = var.docker_min_runners
  max_runners = var.docker_max_runners

  cpu_request    = var.docker_cpu_request
  memory_request = var.docker_memory_request
  cpu_limit      = var.docker_cpu_limit
  memory_limit   = var.docker_memory_limit

  bazel_cache_endpoint = var.bazel_cache_endpoint

  image_pull_secrets = local.ghcr_pull_secrets

  depends_on = [module.arc_controller, kubernetes_namespace_v1.arc_runners]
}

# =============================================================================
# DinD Runner - runs-on: tinyland-dind
# =============================================================================

module "gh_dind" {
  source = "../../modules/arc-runner"
  count  = var.deploy_dind_runner ? 1 : 0

  runner_name          = var.dind_runner_name
  runner_label         = "tinyland-dind"
  runner_type          = "dind"
  container_mode       = "dind"
  namespace            = var.runner_namespace
  controller_namespace = var.controller_namespace
  github_config_url    = var.github_config_url
  github_config_secret = var.github_config_secret

  min_runners = var.dind_min_runners
  max_runners = var.dind_max_runners

  cpu_request    = var.dind_cpu_request
  memory_request = var.dind_memory_request
  cpu_limit      = var.dind_cpu_limit
  memory_limit   = var.dind_memory_limit

  image_pull_secrets = local.ghcr_pull_secrets

  depends_on = [module.arc_controller, kubernetes_namespace_v1.arc_runners]
}

# =============================================================================
# Extra Runner Scale Sets (multi-org / cross-repo)
# =============================================================================

module "extra_runners" {
  source   = "../../modules/arc-runner"
  for_each = var.extra_runner_sets

  runner_name          = each.key
  runner_label         = each.value.runner_label
  runner_type          = each.value.runner_type
  container_mode       = each.value.container_mode
  runner_image         = each.value.runner_image
  namespace            = var.runner_namespace
  controller_namespace = var.controller_namespace
  github_config_url    = each.value.github_config_url
  github_config_secret = each.value.github_config_secret
  min_runners          = each.value.min_runners
  max_runners          = each.value.max_runners
  cpu_request          = each.value.cpu_request
  memory_request       = each.value.memory_request
  cpu_limit            = each.value.cpu_limit
  memory_limit         = each.value.memory_limit
  attic_server         = each.value.attic_server
  attic_cache          = each.value.attic_cache
  bazel_cache_endpoint = each.value.bazel_cache_endpoint
  image_pull_secrets   = local.ghcr_pull_secrets

  depends_on = [module.arc_controller, kubernetes_namespace_v1.arc_runners]
}

# =============================================================================
# GHCR Registry Auth (imagePullSecret)
# =============================================================================

resource "kubernetes_secret" "ghcr_auth_controller" {
  count = var.ghcr_token != "" ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.ghcr_username != ""
      error_message = "ghcr_username is required when ghcr_token is set"
    }
  }

  metadata {
    name      = "ghcr-auth"
    namespace = var.controller_namespace

    labels = {
      "app.kubernetes.io/name"       = "ghcr-auth"
      "app.kubernetes.io/component"  = "registry-credentials"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          auth = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
  }

  depends_on = [module.arc_controller]
}

resource "kubernetes_secret" "ghcr_auth_runners" {
  count = var.ghcr_token != "" ? 1 : 0

  metadata {
    name      = "ghcr-auth"
    namespace = var.runner_namespace

    labels = {
      "app.kubernetes.io/name"       = "ghcr-auth"
      "app.kubernetes.io/component"  = "registry-credentials"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          auth = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace_v1.arc_runners]
}

locals {
  ghcr_pull_secrets = var.ghcr_token != "" ? ["ghcr-auth"] : []
}
