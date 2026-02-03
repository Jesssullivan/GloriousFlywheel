# GitLab Runners Stack
#
# Deploys GitLab Runners to Bates Kubernetes clusters (beehive/rigel)
# for CI/CD pipeline execution.
#
# Runners:
#   - nix-runner: For Nix build jobs (tags: nix, kubernetes)
#   - k8s-runner: For kubectl/tofu deployments (tags: kubernetes, tofu, kubectl)
#
# Authentication:
#   - GitLab Kubernetes Agent for cluster access
#   - GitLab API token for headless runner registration
#
# Usage:
#   cd tofu/stacks/gitlab-runners
#   tofu init
#   tofu plan -var-file=beehive.tfvars
#   tofu apply -var-file=beehive.tfvars

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

# =============================================================================
# Kubernetes Provider Configuration (GitLab Kubernetes Agent)
# =============================================================================

provider "kubernetes" {
  config_path    = var.k8s_config_path != "" ? var.k8s_config_path : null
  config_context = var.cluster_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.k8s_config_path != "" ? var.k8s_config_path : "~/.kube/config"
    config_context = var.cluster_context
  }
}

# =============================================================================
# Nix Runner - For Nix Build Jobs
# =============================================================================
# Primary runner for Nix flake builds and cache operations.
# Uses custom values to mount /nix as emptyDir for store operations.

module "nix_runner" {
  source = "../../modules/gitlab-runner"

  runner_name      = "nix-runner"
  namespace        = var.namespace
  create_namespace = true

  gitlab_url       = var.gitlab_url
  gitlab_api_token = var.gitlab_api_token
  project_id       = var.project_id

  runner_tags  = ["nix", "kubernetes"]
  run_untagged = false
  locked       = false

  privileged      = false
  concurrent_jobs = var.nix_concurrent_jobs
  chart_version   = var.runner_chart_version

  cpu_request    = var.nix_cpu_request
  memory_request = var.nix_memory_request
  cpu_limit      = var.nix_cpu_limit
  memory_limit   = var.nix_memory_limit

  # Custom configuration for Nix builds
  additional_values = <<-YAML
    runners:
      config: |
        [[runners]]
          name = "nix-runner"
          executor = "kubernetes"
          [runners.kubernetes]
            namespace = "${var.namespace}"
            # Use nixpkgs/nix which includes /bin/sh (nixos/nix lacks it)
            image = "nixpkgs/nix:nixos-25.05-x86_64-linux"
            image_pull_policy = "IfNotPresent"
            privileged = false
            cpu_request = "100m"
            memory_request = "256Mi"
            # Mount emptyDir for Nix store
            [[runners.kubernetes.volumes.empty_dir]]
              name = "nix-store"
              mount_path = "/nix"
            # Pod labels for identification
            [runners.kubernetes.pod_labels]
              "app.kubernetes.io/name" = "nix-runner-job"
              "app.kubernetes.io/managed-by" = "gitlab-runner"
    concurrent: ${var.nix_concurrent_jobs}
    checkInterval: 3
    resources:
      requests:
        cpu: "${var.nix_cpu_request}"
        memory: "${var.nix_memory_request}"
      limits:
        cpu: "${var.nix_cpu_limit}"
        memory: "${var.nix_memory_limit}"
  YAML
}

# =============================================================================
# K8s Runner - For Kubernetes Deployments
# =============================================================================
# Secondary runner for kubectl and tofu deployment operations.
# Has cluster-wide RBAC access for deploying to any namespace.

module "k8s_runner" {
  source = "../../modules/gitlab-runner"
  count  = var.deploy_k8s_runner ? 1 : 0

  runner_name      = "k8s-runner"
  namespace        = var.namespace
  create_namespace = false

  depends_on = [module.nix_runner]

  gitlab_url       = var.gitlab_url
  gitlab_api_token = var.gitlab_api_token
  project_id       = var.project_id

  runner_tags         = ["kubernetes", "tofu", "kubectl"]
  run_untagged        = false
  locked              = false
  privileged          = false
  concurrent_jobs     = var.k8s_concurrent_jobs
  cluster_wide_access = true
  chart_version       = var.runner_chart_version

  cpu_request    = var.k8s_cpu_request
  memory_request = var.k8s_memory_request
  cpu_limit      = var.k8s_cpu_limit
  memory_limit   = var.k8s_memory_limit

  # Custom configuration for K8s deployments
  additional_values = <<-YAML
    runners:
      config: |
        [[runners]]
          name = "k8s-runner"
          executor = "kubernetes"
          [runners.kubernetes]
            namespace = "${var.namespace}"
            image = "alpine/k8s:1.29.0"
            image_pull_policy = "IfNotPresent"
            privileged = false
            cpu_request = "100m"
            memory_request = "128Mi"
            # Pod labels for identification
            [runners.kubernetes.pod_labels]
              "app.kubernetes.io/name" = "k8s-runner-job"
              "app.kubernetes.io/managed-by" = "gitlab-runner"
    concurrent: ${var.k8s_concurrent_jobs}
    checkInterval: 3
    resources:
      requests:
        cpu: "${var.k8s_cpu_request}"
        memory: "${var.k8s_memory_request}"
      limits:
        cpu: "${var.k8s_cpu_limit}"
        memory: "${var.k8s_memory_limit}"
    rbac:
      create: true
      clusterWideAccess: true
  YAML
}

# =============================================================================
# Outputs
# =============================================================================

output "namespace" {
  description = "Kubernetes namespace for runners"
  value       = var.namespace
}

output "nix_runner" {
  description = "Nix runner configuration"
  value = {
    name            = module.nix_runner.runner_name
    tags            = module.nix_runner.runner_tags
    concurrent_jobs = module.nix_runner.concurrent_jobs
  }
}

output "k8s_runner" {
  description = "K8s runner configuration (if deployed)"
  value = var.deploy_k8s_runner ? {
    name            = module.k8s_runner[0].runner_name
    tags            = module.k8s_runner[0].runner_tags
    concurrent_jobs = module.k8s_runner[0].concurrent_jobs
  } : null
}

output "cluster_context" {
  description = "Kubernetes cluster context used"
  value       = var.cluster_context
}
