# Runner Dashboard Module
#
# Deploys the GitLab Runner Dashboard web application to Kubernetes.
# Provides a real-time monitoring UI for GitLab runners with OAuth login.
#
# Usage:
#   module "runner_dashboard" {
#     source = "../../modules/runner-dashboard"
#
#     namespace      = "runner-dashboard"
#     image          = "registry.gitlab.com/myorg/runner-dashboard:latest"
#     ingress_host   = "runner-dashboard.example.com"
#     runners_namespace = "gitlab-runners"
#
#     gitlab_oauth_client_id     = var.gitlab_oauth_client_id
#     gitlab_oauth_client_secret = var.gitlab_oauth_client_secret
#     gitlab_oauth_redirect_uri  = "https://runner-dashboard.example.com/auth/callback"
#     gitlab_url                 = "https://gitlab.com"
#     gitlab_token               = var.gitlab_token
#     prometheus_url             = "http://prometheus.monitoring.svc.cluster.local:9090"
#   }

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# Auto-generated Session Secret (when not provided)
# =============================================================================

resource "random_password" "session_secret" {
  count   = var.session_secret == "" ? 1 : 0
  length  = 32
  special = false
}

locals {
  effective_session_secret = var.session_secret != "" ? var.session_secret : random_password.session_secret[0].result
}

# =============================================================================
# Computed Values
# =============================================================================

locals {
  # Determine effective image pull secret name
  effective_pull_secret = var.image_pull_secret_name != "" ? var.image_pull_secret_name : (
    var.ghcr_token != "" ? "ghcr-auth" : ""
  )
}

locals {
  labels = merge(
    {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/instance"   = "${var.name}-${var.namespace}"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/component"  = "dashboard"
    },
    var.additional_labels
  )

  selector_labels = {
    "app.kubernetes.io/name"     = var.name
    "app.kubernetes.io/instance" = "${var.name}-${var.namespace}"
  }
}

# =============================================================================
# Namespace
# =============================================================================

resource "kubernetes_namespace" "dashboard" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/component"  = "dashboard"
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/part-of"    = "runner-dashboard"
      "kubernetes.io/metadata.name"  = var.namespace
      # Pod Security Standards
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }

    annotations = {
      "description" = "GitLab Runner Dashboard with monitoring and management UI"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["kubectl.kubernetes.io/last-applied-configuration"],
    ]
  }
}

locals {
  namespace_name = var.create_namespace ? kubernetes_namespace.dashboard[0].metadata[0].name : var.namespace
}

# =============================================================================
# ConfigMap - Non-sensitive environment variables
# =============================================================================

resource "kubernetes_config_map" "dashboard" {
  metadata {
    name      = "${var.name}-config"
    namespace = local.namespace_name

    labels = local.labels
  }

  data = merge(
    {
      NODE_ENV                  = var.node_env
      PORT                      = tostring(var.container_port)
      GITLAB_URL                = var.gitlab_url
      GITLAB_OAUTH_REDIRECT_URI = var.gitlab_oauth_redirect_uri
      PROMETHEUS_URL            = var.prometheus_url
      RUNNERS_NAMESPACE         = var.runners_namespace
      K8S_NAMESPACE             = var.runners_namespace
      GITLAB_GROUP_ID           = var.gitlab_group_id
      GITLAB_PROJECT_ID         = var.gitlab_project_id
      RUNNER_STACK_NAME         = var.runner_stack_name
      ATTIC_DEFAULT_ENV         = var.default_env
      LOG_LEVEL                 = var.log_level
    },
    var.webauthn_rp_id != "" ? {
      WEBAUTHN_RP_ID   = var.webauthn_rp_id
      WEBAUTHN_RP_NAME = var.webauthn_rp_name
    } : {},
    var.trust_proxy_headers ? {
      TRUST_PROXY_HEADERS = "true"
    } : {},
  )
}

# =============================================================================
# Secret - Sensitive environment variables
# =============================================================================

resource "kubernetes_secret" "dashboard" {
  metadata {
    name      = "${var.name}-secrets"
    namespace = local.namespace_name

    labels = local.labels
  }

  data = merge(
    {
      GITLAB_OAUTH_CLIENT_ID     = var.gitlab_oauth_client_id
      GITLAB_OAUTH_CLIENT_SECRET = var.gitlab_oauth_client_secret
      GITLAB_TOKEN               = var.gitlab_token
      SESSION_SECRET             = local.effective_session_secret
    },
    var.database_url != "" ? {
      DATABASE_URL = var.database_url
    } : {},
  )

  type = "Opaque"
}

# =============================================================================
# GHCR Registry Auth (imagePullSecret)
# =============================================================================

resource "kubernetes_secret" "ghcr_auth" {
  count = var.ghcr_token != "" ? 1 : 0

  metadata {
    name      = "ghcr-auth"
    namespace = local.namespace_name
    labels    = local.labels
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
}

# =============================================================================
# Environments ConfigMap (runtime config)
# =============================================================================

# =============================================================================
# Caddy Proxy ConfigMap (when enabled)
# =============================================================================

resource "kubernetes_config_map" "caddyfile" {
  count = var.enable_caddy_proxy ? 1 : 0

  metadata {
    name      = "${var.name}-caddyfile"
    namespace = local.namespace_name
    labels    = local.labels
  }

  data = {
    "Caddyfile" = templatefile("${path.module}/templates/Caddyfile.tpl", {
      mode                  = var.caddy_mode
      port                  = var.caddy_port
      backend_port          = var.container_port
      mtls_client_auth_mode = var.caddy_mtls_client_auth_mode
      tailscale_hostname    = var.caddy_tailscale_hostname
    })
  }
}

# =============================================================================
# Caddy Proxy Secrets (when enabled)
# =============================================================================

resource "kubernetes_secret" "caddy_secrets" {
  count = var.enable_caddy_proxy ? 1 : 0

  metadata {
    name      = "${var.name}-caddy-secrets"
    namespace = local.namespace_name
    labels    = local.labels
  }

  data = merge(
    var.caddy_mtls_ca_cert != "" ? { "ca.pem" = var.caddy_mtls_ca_cert } : {},
    var.caddy_tailscale_auth_key != "" ? { "TS_AUTHKEY" = var.caddy_tailscale_auth_key } : {},
  )

  type = "Opaque"
}

resource "kubernetes_config_map" "environments" {
  count = var.environments_config != "" ? 1 : 0

  metadata {
    name      = "${var.name}-environments"
    namespace = local.namespace_name
    labels    = local.labels
  }

  data = {
    "environments.json" = var.environments_config
  }
}

# =============================================================================
# Deployment
# =============================================================================

resource "kubernetes_deployment" "dashboard" {
  wait_for_rollout = var.wait_for_rollout

  metadata {
    name      = var.name
    namespace = local.namespace_name
    labels    = local.labels

    annotations = {
      "app.kubernetes.io/created-by" = "opentofu"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.selector_labels
    }

    template {
      metadata {
        labels = local.labels

        annotations = merge(
          {
            "prometheus.io/scrape" = tostring(var.enable_prometheus_scrape)
            "prometheus.io/port"   = tostring(var.enable_caddy_proxy ? var.caddy_port : var.container_port)
            "prometheus.io/path"   = "/metrics"
          },
          {
            # Force pod restart when config or secrets change
            "checksum/config"  = sha256(jsonencode(kubernetes_config_map.dashboard.data))
            "checksum/secrets" = sha256(jsonencode(kubernetes_secret.dashboard.data))
          },
          var.enable_caddy_proxy ? {
            "checksum/caddyfile" = sha256(jsonencode(kubernetes_config_map.caddyfile[0].data))
          } : {}
        )
      }

      spec {
        service_account_name = kubernetes_service_account.dashboard.metadata[0].name

        dynamic "image_pull_secrets" {
          for_each = toset(local.effective_pull_secret != "" ? [local.effective_pull_secret] : [])
          content {
            name = image_pull_secrets.value
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
        }

        # Caddy reverse proxy sidecar container
        dynamic "container" {
          for_each = var.enable_caddy_proxy ? toset(["enabled"]) : toset([])
          content {
            name  = "caddy-proxy"
            image = var.caddy_image

            port {
              container_port = var.caddy_port
              name           = "caddy"
              protocol       = "TCP"
            }

            volume_mount {
              name       = "caddyfile"
              mount_path = "/etc/caddy"
              read_only  = true
            }

            volume_mount {
              name       = "caddy-config"
              mount_path = "/config"
            }

            volume_mount {
              name       = "caddy-data"
              mount_path = "/data"
            }

            dynamic "volume_mount" {
              for_each = { for k in ["mtls"] : k => k if var.caddy_mtls_ca_cert != "" }
              content {
                name       = "caddy-mtls"
                mount_path = "/etc/caddy/mtls"
                read_only  = true
              }
            }

            dynamic "env" {
              for_each = { for k in ["ts"] : k => k if var.caddy_tailscale_auth_key != "" }
              content {
                name = "TS_AUTHKEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.caddy_secrets[0].metadata[0].name
                    key  = "TS_AUTHKEY"
                  }
                }
              }
            }

            resources {
              requests = {
                cpu    = var.caddy_cpu_request
                memory = var.caddy_memory_request
              }
              limits = {
                cpu    = var.caddy_cpu_limit
                memory = var.caddy_memory_limit
              }
            }

            security_context {
              allow_privilege_escalation = false
              read_only_root_filesystem  = true
              capabilities {
                drop = ["ALL"]
              }
            }
          }
        }

        container {
          name  = var.name
          image = var.image

          port {
            container_port = var.container_port
            name           = "http"
            protocol       = "TCP"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.dashboard.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.dashboard.metadata[0].name
            }
          }

          # Direct environment variables (overrides)
          dynamic "env" {
            for_each = var.environment_variables
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          # Liveness probe
          liveness_probe {
            http_get {
              path = var.health_check_path
              port = var.container_port
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          # Readiness probe
          readiness_probe {
            http_get {
              path = var.health_check_path
              port = var.container_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          # Mount environments config if provided
          dynamic "volume_mount" {
            for_each = var.environments_config != "" ? toset(["enabled"]) : toset([])
            content {
              name       = "environments-config"
              mount_path = "/etc/dashboard"
              read_only  = true
            }
          }

          # Set config path env var when ConfigMap is mounted
          dynamic "env" {
            for_each = var.environments_config != "" ? toset(["enabled"]) : toset([])
            content {
              name  = "ENVIRONMENTS_CONFIG_PATH"
              value = "/etc/dashboard/environments.json"
            }
          }

          # Trust K8s cluster CA for in-cluster API calls
          env {
            name  = "NODE_EXTRA_CA_CERTS"
            value = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
          }

          # Bind SvelteKit to loopback when Caddy proxy is in front
          dynamic "env" {
            for_each = var.enable_caddy_proxy ? toset(["enabled"]) : toset([])
            content {
              name  = "HOST"
              value = "127.0.0.1"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        # Volume for environments ConfigMap
        dynamic "volume" {
          for_each = var.environments_config != "" ? toset(["enabled"]) : toset([])
          content {
            name = "environments-config"
            config_map {
              name = kubernetes_config_map.environments[0].metadata[0].name
            }
          }
        }

        # Volume for Caddyfile ConfigMap
        dynamic "volume" {
          for_each = var.enable_caddy_proxy ? toset(["enabled"]) : toset([])
          content {
            name = "caddyfile"
            config_map {
              name = kubernetes_config_map.caddyfile[0].metadata[0].name
            }
          }
        }

        # Volume for mTLS CA cert
        dynamic "volume" {
          for_each = var.enable_caddy_proxy && var.caddy_mtls_ca_cert != "" ? toset(["enabled"]) : toset([])
          content {
            name = "caddy-mtls"
            secret {
              secret_name = kubernetes_secret.caddy_secrets[0].metadata[0].name
              items {
                key  = "ca.pem"
                path = "ca.pem"
              }
            }
          }
        }

        # Writable volumes for Caddy state (Tailscale node state + Caddy runtime data)
        dynamic "volume" {
          for_each = var.enable_caddy_proxy ? toset(["enabled"]) : toset([])
          content {
            name = "caddy-config"
            empty_dir {}
          }
        }

        dynamic "volume" {
          for_each = var.enable_caddy_proxy ? toset(["enabled"]) : toset([])
          content {
            name = "caddy-data"
            empty_dir {}
          }
        }

        # Node selector
        node_selector = length(var.node_selector) > 0 ? var.node_selector : null
      }
    }
  }

  depends_on = [
    kubernetes_config_map.dashboard,
    kubernetes_secret.dashboard,
    kubernetes_service_account.dashboard
  ]
}

# =============================================================================
# Service
# =============================================================================

resource "kubernetes_service" "dashboard" {
  metadata {
    name      = var.name
    namespace = local.namespace_name
    labels    = local.labels
  }

  spec {
    selector = local.selector_labels

    port {
      port        = var.service_port
      target_port = var.enable_caddy_proxy ? var.caddy_port : var.container_port
      name        = "http"
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# =============================================================================
# Ingress
# =============================================================================

resource "kubernetes_ingress_v1" "dashboard" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace_name
    labels    = local.labels

    annotations = merge(
      {
        "cert-manager.io/cluster-issuer" = var.cert_manager_issuer
      },
      var.ingress_annotations
    )
  }

  spec {
    ingress_class_name = var.ingress_class

    dynamic "tls" {
      for_each = var.enable_tls ? toset(["enabled"]) : toset([])
      content {
        hosts       = [var.ingress_host]
        secret_name = "${var.name}-tls"
      }
    }

    rule {
      host = var.ingress_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.dashboard.metadata[0].name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }
  }
}
