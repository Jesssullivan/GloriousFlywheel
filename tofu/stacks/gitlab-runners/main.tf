# GitLab Runners Stack - Beehive Deployment
#
# Deploys self-hosted GitLab Runners to the beehive Kubernetes cluster.
# Runners are registered via tokens created in GitLab UI.

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
# Nix Runner - For Nix build jobs
# =============================================================================

module "nix_runner" {
  source = "../../modules/gitlab-runner"

  runner_name      = "nix-runner"
  namespace        = var.namespace
  create_namespace = var.create_namespace

  gitlab_url   = var.gitlab_url
  runner_token = var.nix_runner_token

  runner_tags  = ["nix", "kubernetes"]
  privileged   = false
  concurrent_jobs = var.nix_concurrent_jobs

  cpu_request    = var.nix_cpu_request
  memory_request = var.nix_memory_request

  additional_values = yamlencode({
    runners = {
      config = <<-TOML
        [[runners]]
          [runners.kubernetes]
            namespace = "${var.namespace}"
            image = "alpine:3.21"
            [[runners.kubernetes.volumes.empty_dir]]
              name = "nix-store"
              mount_path = "/nix"
      TOML
    }
  })
}

# =============================================================================
# K8s Runner - For kubectl/tofu deployment jobs
# =============================================================================

module "k8s_runner" {
  source = "../../modules/gitlab-runner"
  count  = var.deploy_k8s_runner ? 1 : 0

  runner_name      = "k8s-runner"
  namespace        = var.namespace
  create_namespace = false

  depends_on = [module.nix_runner]

  gitlab_url   = var.gitlab_url
  runner_token = var.k8s_runner_token

  runner_tags         = ["kubernetes", "tofu", "kubectl"]
  privileged          = false
  concurrent_jobs     = var.k8s_concurrent_jobs
  cluster_wide_access = true

  cpu_request    = "100m"
  memory_request = "256Mi"
}
