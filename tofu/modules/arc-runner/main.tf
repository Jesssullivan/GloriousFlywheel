# ARC Runner Module
#
# Deploys a GitHub Actions runner scale set via ARC (Actions Runner Controller).
# Each instance provides one `runs-on` label for GitHub Actions workflows.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# =============================================================================
# ARC Runner Scale Set Helm Release
# =============================================================================

resource "helm_release" "arc_runner" {
  name       = var.runner_name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = 600

  # GitHub App configuration
  set {
    name  = "githubConfigUrl"
    value = var.github_config_url
  }

  set {
    name  = "githubConfigSecret"
    value = var.github_config_secret
  }

  # Runner identity
  set {
    name  = "runnerScaleSetName"
    value = var.runner_label
  }

  set {
    name  = "runnerGroup"
    value = var.runner_group
  }

  # Autoscaling
  set {
    name  = "minRunners"
    value = tostring(var.min_runners)
  }

  set {
    name  = "maxRunners"
    value = tostring(var.max_runners)
  }

  # Controller service account (explicit to avoid ambiguity with multiple controllers)
  set {
    name  = "controllerServiceAccount.namespace"
    value = var.controller_namespace
  }

  set {
    name  = "controllerServiceAccount.name"
    value = var.controller_service_account_name
  }

  # Container mode: kubernetes (supports `container:` in workflows) or dind (privileged Docker)
  # Without this, the ARC Helm chart defaults to no container mode and the
  # workflow `container:` directive silently fails looking for a Docker daemon.
  dynamic "set" {
    for_each = local.container_mode != "" ? [1] : []
    content {
      name  = "containerMode.type"
      value = local.container_mode
    }
  }

  # Pod template via values block
  values = [
    yamlencode({
      template = {
        spec = merge(
          {
            containers = [
              merge(
                {
                  name    = "runner"
                  image   = local.runner_image
                  command = ["/home/runner/run.sh"]
                  resources = {
                    requests = {
                      cpu    = var.cpu_request
                      memory = var.memory_request
                    }
                    limits = {
                      cpu    = var.cpu_limit
                      memory = var.memory_limit
                    }
                  }
                },
                length(local.all_env_vars) > 0 ? {
                  env = local.all_env_vars
                } : {},
              )
            ]
          },
          length(var.node_selector) > 0 ? {
            nodeSelector = var.node_selector
          } : {},
          length(var.tolerations) > 0 ? {
            tolerations = [
              for t in var.tolerations : merge(
                {
                  key      = t.key
                  operator = t.operator
                  effect   = t.effect
                },
                t.value != null ? { value = t.value } : {},
              )
            ]
          } : {},
          length(var.image_pull_secrets) > 0 ? {
            imagePullSecrets = [
              for s in var.image_pull_secrets : { name = s }
            ]
          } : {},
        )
      }
    })
  ]
}
