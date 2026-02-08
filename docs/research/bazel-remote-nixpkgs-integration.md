# Bazel Remote Cache & rules_nixpkgs Integration Design

**Date:** 2026-02-05
**Status:** Research Complete - Ready for Implementation
**Author:** IaC Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [bazel-remote Module Design](#2-bazel-remote-module-design)
3. [rules_nixpkgs Integration Patterns](#3-rules_nixpkgs-integration-patterns)
4. [Example Project Setup](#4-example-project-setup)
5. [Remote Execution Considerations](#5-remote-execution-considerations)
6. [Implementation Roadmap](#6-implementation-roadmap)

---

## 1. Executive Summary

This document provides a comprehensive design for adding Bazel remote caching capabilities to the GloriousFlywheel IaC infrastructure, alongside deep integration patterns for using Nix-provided toolchains in Bazel builds via `rules_nixpkgs`.

### Key Decisions

| Decision         | Choice               | Rationale                                              |
| ---------------- | -------------------- | ------------------------------------------------------ |
| Cache Server     | bazel-remote         | Battle-tested, direct MinIO support, simple deployment |
| Storage Backend  | Existing MinIO       | Reuse `attic-cache` namespace MinIO, separate bucket   |
| Nix Integration  | rules_nixpkgs 0.13.0 | Bzlmod support, toolchain coverage                     |
| Remote Execution | Deferred             | Cache-only provides 80% benefit at 20% complexity      |

### Resource Requirements

| Component     | Replicas   | CPU        | Memory  | Notes                             |
| ------------- | ---------- | ---------- | ------- | --------------------------------- |
| bazel-remote  | 2          | 500m/1000m | 1Gi/2Gi | Request/Limit                     |
| MinIO bucket  | -          | -          | -       | Uses existing `attic-cache` MinIO |
| **New Total** | **2 pods** | **1 CPU**  | **2Gi** | Minimal footprint                 |

---

## 2. bazel-remote Module Design

### 2.1 Module Structure

```
tofu/modules/bazel-cache/
├── main.tf           # Deployment, Service, ConfigMap
├── variables.tf      # Input variables with validation
├── outputs.tf        # Service endpoints, status
├── hpa.tf            # Horizontal Pod Autoscaler
├── monitoring.tf     # ServiceMonitor, PrometheusRules
└── network-policy.tf # NetworkPolicy for security
```

### 2.2 Main Configuration (`main.tf`)

```hcl
# bazel-cache Module
#
# Deploys bazel-remote cache server with S3/MinIO backend.
# Optimized for Kubernetes environments with HPA and monitoring.
#
# Usage:
#   module "bazel_cache" {
#     source = "../../modules/bazel-cache"
#
#     name      = "bazel-cache"
#     namespace = "attic-cache"
#
#     # MinIO backend (existing in namespace)
#     s3_endpoint   = "minio.attic-cache.svc.cluster.local:9000"
#     s3_bucket     = "bazel-cache"
#     s3_secret     = "bazel-cache-s3-credentials"
#
#     # Scaling
#     min_replicas = 2
#     max_replicas = 4
#   }

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  labels = merge(
    {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/instance"   = "${var.name}-${var.namespace}"
      "app.kubernetes.io/component"  = "build-cache"
      "app.kubernetes.io/part-of"    = "build-infrastructure"
      "app.kubernetes.io/managed-by" = "opentofu"
    },
    var.additional_labels
  )

  selector_labels = {
    "app.kubernetes.io/name"     = var.name
    "app.kubernetes.io/instance" = "${var.name}-${var.namespace}"
  }

  # Service endpoints
  grpc_port = 9092
  http_port = 8080
}

# =============================================================================
# ConfigMap for bazel-remote configuration
# =============================================================================

resource "kubernetes_config_map" "config" {
  metadata {
    name      = "${var.name}-config"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "config.yaml" = yamlencode({
      # Storage configuration
      dir      = "/data"
      max_size = var.max_cache_size_gb

      # gRPC settings
      grpc_port = local.grpc_port

      # HTTP settings
      http_address = "0.0.0.0:${local.http_port}"

      # S3/MinIO backend
      s3_proxy = {
        endpoint         = var.s3_endpoint
        bucket           = var.s3_bucket
        prefix           = var.s3_prefix
        auth_method      = "access_key"
        disable_ssl      = var.s3_disable_ssl
        bucket_lookup_type = var.s3_bucket_lookup_type
        max_idle_conns   = var.s3_max_idle_conns
        update_timestamps = var.s3_update_timestamps
      }

      # Performance tuning
      num_uploaders      = var.num_uploaders
      max_queued_uploads = var.max_queued_uploads

      # Metrics
      enable_endpoint_metrics = var.enable_metrics

      # Access logging
      access_log_level = var.access_log_level
    })
  }
}

# =============================================================================
# Deployment
# =============================================================================

resource "kubernetes_deployment" "main" {
  wait_for_rollout = var.wait_for_rollout

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels

    annotations = {
      "app.kubernetes.io/created-by" = "opentofu"
    }
  }

  spec {
    replicas = var.min_replicas

    selector {
      match_labels = local.selector_labels
    }

    template {
      metadata {
        labels = local.labels

        annotations = {
          "prometheus.io/scrape" = tostring(var.enable_metrics)
          "prometheus.io/port"   = tostring(local.http_port)
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = var.service_account_name

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
        }

        container {
          name  = "bazel-remote"
          image = var.image

          args = ["--config_file=/etc/bazel-remote/config.yaml"]

          port {
            container_port = local.grpc_port
            name           = "grpc"
            protocol       = "TCP"
          }

          port {
            container_port = local.http_port
            name           = "http"
            protocol       = "TCP"
          }

          # S3 credentials from secret
          env {
            name = "BAZEL_REMOTE_S3_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = var.s3_secret
                key  = "access-key"
              }
            }
          }

          env {
            name = "BAZEL_REMOTE_S3_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = var.s3_secret
                key  = "secret-key"
              }
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/bazel-remote"
            read_only  = true
          }

          volume_mount {
            name       = "cache"
            mount_path = "/data"
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

          # Liveness probe using gRPC health check
          liveness_probe {
            grpc {
              port = local.grpc_port
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          # Readiness probe
          readiness_probe {
            http_get {
              path = "/status"
              port = local.http_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
          }
        }

        volume {
          name = "cache"
          empty_dir {
            size_limit = "${var.local_cache_size_gb}Gi"
          }
        }

        # Topology spread for HA
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = local.selector_labels
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].replicas, # Managed by HPA
    ]
  }
}

# =============================================================================
# Service
# =============================================================================

resource "kubernetes_service" "main" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    selector = local.selector_labels

    port {
      port        = local.grpc_port
      target_port = local.grpc_port
      name        = "grpc"
      protocol    = "TCP"
    }

    port {
      port        = local.http_port
      target_port = local.http_port
      name        = "http"
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# =============================================================================
# Ingress (optional, for external access)
# =============================================================================

resource "kubernetes_ingress_v1" "main" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels

    annotations = merge(
      {
        "kubernetes.io/ingress.class"    = var.ingress_class
        "cert-manager.io/cluster-issuer" = var.cert_manager_issuer
        # gRPC requires HTTP/2
        "nginx.ingress.kubernetes.io/backend-protocol" = "GRPC"
      },
      var.ingress_annotations
    )
  }

  spec {
    ingress_class_name = var.ingress_class

    tls {
      hosts       = [var.ingress_host]
      secret_name = "${var.name}-tls"
    }

    rule {
      host = var.ingress_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.main.metadata[0].name
              port {
                number = local.grpc_port
              }
            }
          }
        }
      }
    }
  }
}
```

### 2.3 Variables (`variables.tf`)

```hcl
# bazel-cache Module - Variables

# =============================================================================
# Required Variables
# =============================================================================

variable "name" {
  description = "Name of the bazel-remote deployment"
  type        = string
  default     = "bazel-cache"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "Name must be lowercase alphanumeric with optional hyphens"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string
}

# =============================================================================
# S3/MinIO Configuration
# =============================================================================

variable "s3_endpoint" {
  description = "S3/MinIO endpoint (e.g., minio.attic-cache.svc.cluster.local:9000)"
  type        = string
}

variable "s3_bucket" {
  description = "S3/MinIO bucket name for cache storage"
  type        = string
  default     = "bazel-cache"
}

variable "s3_secret" {
  description = "Kubernetes secret name containing access-key and secret-key"
  type        = string
}

variable "s3_prefix" {
  description = "Object prefix within the bucket"
  type        = string
  default     = ""
}

variable "s3_disable_ssl" {
  description = "Disable SSL for S3/MinIO (true for internal MinIO)"
  type        = bool
  default     = true
}

variable "s3_bucket_lookup_type" {
  description = "S3 bucket lookup type: auto, dns, or path"
  type        = string
  default     = "path"

  validation {
    condition     = contains(["auto", "dns", "path"], var.s3_bucket_lookup_type)
    error_message = "s3_bucket_lookup_type must be auto, dns, or path"
  }
}

variable "s3_max_idle_conns" {
  description = "Maximum idle connections to S3"
  type        = number
  default     = 1024
}

variable "s3_update_timestamps" {
  description = "Update object timestamps on cache hit"
  type        = bool
  default     = true
}

# =============================================================================
# Cache Configuration
# =============================================================================

variable "max_cache_size_gb" {
  description = "Maximum cache size in GB (for S3 LRU eviction)"
  type        = number
  default     = 100
}

variable "local_cache_size_gb" {
  description = "Local disk cache size in GB (ephemeral, for faster reads)"
  type        = number
  default     = 10
}

variable "num_uploaders" {
  description = "Number of parallel S3 upload goroutines"
  type        = number
  default     = 100
}

variable "max_queued_uploads" {
  description = "Maximum queued uploads before blocking"
  type        = number
  default     = 1000000
}

# =============================================================================
# Container Configuration
# =============================================================================

variable "image" {
  description = "bazel-remote container image"
  type        = string
  default     = "buchgr/bazel-remote-cache:v2.4.4"
}

variable "cpu_request" {
  description = "CPU request per replica"
  type        = string
  default     = "250m"
}

variable "cpu_limit" {
  description = "CPU limit per replica"
  type        = string
  default     = "1000m"
}

variable "memory_request" {
  description = "Memory request per replica"
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "Memory limit per replica"
  type        = string
  default     = "2Gi"
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
  default     = "default"
}

variable "wait_for_rollout" {
  description = "Wait for deployment rollout to complete"
  type        = bool
  default     = true
}

# =============================================================================
# Scaling Configuration
# =============================================================================

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.min_replicas >= 1
    error_message = "min_replicas must be at least 1"
  }
}

variable "max_replicas" {
  description = "Maximum number of replicas for HPA"
  type        = number
  default     = 4

  validation {
    condition     = var.max_replicas >= 1
    error_message = "max_replicas must be at least 1"
  }
}

variable "cpu_target_percent" {
  description = "Target CPU utilization for HPA"
  type        = number
  default     = 70
}

variable "memory_target_percent" {
  description = "Target memory utilization for HPA"
  type        = number
  default     = 80
}

# =============================================================================
# Ingress Configuration
# =============================================================================

variable "enable_ingress" {
  description = "Create Ingress for external access"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname for Ingress"
  type        = string
  default     = ""
}

variable "ingress_class" {
  description = "Ingress class (nginx, traefik)"
  type        = string
  default     = "nginx"
}

variable "cert_manager_issuer" {
  description = "cert-manager ClusterIssuer name"
  type        = string
  default     = "letsencrypt-prod"
}

variable "ingress_annotations" {
  description = "Additional Ingress annotations"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "enable_metrics" {
  description = "Enable Prometheus metrics endpoint"
  type        = bool
  default     = true
}

variable "access_log_level" {
  description = "Access log level: none or all"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "all"], var.access_log_level)
    error_message = "access_log_level must be none or all"
  }
}

variable "create_service_monitor" {
  description = "Create ServiceMonitor for Prometheus Operator"
  type        = bool
  default     = true
}

variable "prometheus_release_label" {
  description = "Label value for Prometheus selector"
  type        = string
  default     = "prometheus"
}

# =============================================================================
# Labels
# =============================================================================

variable "additional_labels" {
  description = "Additional labels for all resources"
  type        = map(string)
  default     = {}
}
```

### 2.4 HPA Configuration (`hpa.tf`)

```hcl
# bazel-cache Module - Horizontal Pod Autoscaler

resource "kubernetes_horizontal_pod_autoscaler_v2" "main" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.main.metadata[0].name
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # CPU-based scaling
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.cpu_target_percent
        }
      }
    }

    # Memory-based scaling
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.memory_target_percent
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 10
          period_seconds = 60
        }
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }

      scale_up {
        stabilization_window_seconds = 0
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 15
        }
        policy {
          type           = "Pods"
          value          = 2
          period_seconds = 15
        }
      }
    }
  }
}
```

### 2.5 Monitoring (`monitoring.tf`)

```hcl
# bazel-cache Module - Prometheus Monitoring

# =============================================================================
# ServiceMonitor
# =============================================================================

resource "kubectl_manifest" "service_monitor" {
  count = var.enable_metrics && var.create_service_monitor ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "${var.name}-metrics"
      namespace = var.namespace
      labels = merge(local.labels, {
        "prometheus" = var.prometheus_release_label
      })
    }
    spec = {
      selector = {
        matchLabels = local.selector_labels
      }
      endpoints = [
        {
          port     = "http"
          interval = "30s"
          path     = "/metrics"
        }
      ]
      namespaceSelector = {
        matchNames = [var.namespace]
      }
    }
  })
}

# =============================================================================
# PrometheusRule for Alerts
# =============================================================================

resource "kubectl_manifest" "prometheus_rules" {
  count = var.enable_metrics && var.create_service_monitor ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "${var.name}-alerts"
      namespace = var.namespace
      labels = merge(local.labels, {
        "prometheus" = var.prometheus_release_label
      })
    }
    spec = {
      groups = [
        {
          name = "${var.name}.rules"
          rules = [
            {
              alert = "BazelCacheDown"
              expr  = "up{job=\"${var.name}\"} == 0"
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Bazel cache ${var.name} is down"
                description = "Bazel cache ${var.name} in namespace ${var.namespace} has been unreachable for more than 5 minutes."
              }
            },
            {
              alert = "BazelCacheHighLatency"
              expr  = "histogram_quantile(0.95, rate(bazel_remote_http_request_duration_seconds_bucket{job=\"${var.name}\"}[5m])) > 1"
              for   = "10m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Bazel cache p95 latency is high"
                description = "Bazel cache ${var.name} has p95 latency > 1s for more than 10 minutes."
              }
            },
            {
              alert = "BazelCacheHighErrorRate"
              expr  = "rate(bazel_remote_http_request_total{job=\"${var.name}\",code=~\"5..\"}[5m]) / rate(bazel_remote_http_request_total{job=\"${var.name}\"}[5m]) > 0.05"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Bazel cache error rate is high"
                description = "Bazel cache ${var.name} has error rate > 5% for more than 5 minutes."
              }
            },
            {
              alert = "BazelCacheS3Errors"
              expr  = "rate(bazel_remote_s3_requests_total{job=\"${var.name}\",status=\"error\"}[5m]) > 1"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Bazel cache S3 backend errors"
                description = "Bazel cache ${var.name} has S3 backend errors for more than 5 minutes."
              }
            }
          ]
        }
      ]
    }
  })
}
```

### 2.6 Outputs (`outputs.tf`)

```hcl
# bazel-cache Module - Outputs

output "service_name" {
  description = "Kubernetes Service name"
  value       = kubernetes_service.main.metadata[0].name
}

output "grpc_endpoint" {
  description = "gRPC endpoint for Bazel remote cache"
  value       = "grpc://${kubernetes_service.main.metadata[0].name}.${var.namespace}.svc.cluster.local:${local.grpc_port}"
}

output "http_endpoint" {
  description = "HTTP endpoint for status and metrics"
  value       = "http://${kubernetes_service.main.metadata[0].name}.${var.namespace}.svc.cluster.local:${local.http_port}"
}

output "bazelrc_config" {
  description = "Configuration lines for .bazelrc"
  value       = <<-EOT
    # Bazel remote cache configuration
    build --remote_cache=grpc://${kubernetes_service.main.metadata[0].name}.${var.namespace}.svc.cluster.local:${local.grpc_port}
    build --remote_upload_local_results=true
    build --remote_download_minimal
  EOT
}

output "external_grpc_endpoint" {
  description = "External gRPC endpoint (if ingress enabled)"
  value       = var.enable_ingress ? "grpcs://${var.ingress_host}:443" : null
}
```

---

## 3. rules_nixpkgs Integration Patterns

### 3.1 MODULE.bazel Configuration

```python
"""MODULE.bazel - Bazel module configuration with Nix toolchains

This configuration integrates Nix-provided toolchains with Bazel using
rules_nixpkgs. All build tools come from Nix, ensuring reproducibility
and consistency with NixOS/nix-darwin systems.
"""

module(
    name = "attic-cache",
    version = "0.1.0",
)

# =============================================================================
# Core Bazel Rules
# =============================================================================

bazel_dep(name = "bazel_skylib", version = "1.8.2")
bazel_dep(name = "rules_pkg", version = "1.1.0")
bazel_dep(name = "rules_shell", version = "0.6.0")
bazel_dep(name = "platforms", version = "0.0.10")

# =============================================================================
# rules_nixpkgs - Nix Toolchain Integration
# =============================================================================

bazel_dep(name = "rules_nixpkgs_core", version = "0.13.0")
bazel_dep(name = "rules_nixpkgs_cc", version = "0.13.0")
bazel_dep(name = "rules_nixpkgs_go", version = "0.13.0")
bazel_dep(name = "rules_nixpkgs_python", version = "0.13.0")
bazel_dep(name = "rules_nixpkgs_rust", version = "0.13.0")

# =============================================================================
# Language Rules (for toolchain consumers)
# =============================================================================

bazel_dep(name = "rules_cc", version = "0.1.1")
bazel_dep(name = "rules_go", version = "0.54.0")
bazel_dep(name = "rules_python", version = "1.3.0")
bazel_dep(name = "rules_rust", version = "0.60.0")

# =============================================================================
# Nix Repository Configuration (via module extension)
# =============================================================================

nix_repo = use_extension("@rules_nixpkgs_core//nixpkgs:extensions.bzl", "nix_repo")

# Use the project's flake.nix as the Nix source
nix_repo.file(
    name = "nixpkgs",
    file = "//:flake.lock",
    file_deps = ["//:flake.nix"],
)

use_repo(nix_repo, "nixpkgs")

# =============================================================================
# CC Toolchain from Nix
# =============================================================================

nix_cc = use_extension("@rules_nixpkgs_cc//toolchains:extensions.bzl", "nix_cc_toolchain")

nix_cc.from_nixpkgs(
    name = "nix_cc_toolchain",
    repository = "@nixpkgs",
    attribute_path = "stdenv.cc",
)

use_repo(nix_cc, "nix_cc_toolchain")

register_toolchains("@nix_cc_toolchain//:all")

# =============================================================================
# Go Toolchain from Nix
# =============================================================================

nix_go = use_extension("@rules_nixpkgs_go//toolchains:extensions.bzl", "nix_go_toolchain")

nix_go.from_nixpkgs(
    name = "nix_go_toolchain",
    repository = "@nixpkgs",
    attribute_path = "go",
)

use_repo(nix_go, "nix_go_toolchain")

register_toolchains("@nix_go_toolchain//:all")

# =============================================================================
# Python Toolchain from Nix
# =============================================================================

nix_python = use_extension("@rules_nixpkgs_python//toolchains:extensions.bzl", "nix_python_toolchain")

nix_python.from_nixpkgs(
    name = "nix_python_toolchain",
    repository = "@nixpkgs",
    attribute_path = "python311",
)

use_repo(nix_python, "nix_python_toolchain")

register_toolchains("@nix_python_toolchain//:all")

# =============================================================================
# Rust Toolchain from Nix
# =============================================================================

nix_rust = use_extension("@rules_nixpkgs_rust//toolchains:extensions.bzl", "nix_rust_toolchain")

nix_rust.from_nixpkgs(
    name = "nix_rust_toolchain",
    repository = "@nixpkgs",
    attribute_path = "rustc",
)

use_repo(nix_rust, "nix_rust_toolchain")

register_toolchains("@nix_rust_toolchain//:all")
```

### 3.2 .bazelrc Best Practices

```bash
# =============================================================================
# Attic Cache - Bazel Configuration
# =============================================================================

# Build settings
build --jobs=auto
build --verbose_failures

# Enable Bzlmod (MODULE.bazel)
common --enable_bzlmod

# =============================================================================
# Platform Configuration (rules_nixpkgs)
# =============================================================================

# Force use of Nix-provided toolchains
common --host_platform=@rules_nixpkgs_core//platforms:host

# Enable CC toolchain resolution
build --incompatible_enable_cc_toolchain_resolution

# =============================================================================
# Nix Integration
# =============================================================================

# Allow access to /nix/store for Nix-built tools
build --sandbox_add_mount_pair=/nix

# Action environment for Nix-aware builds
build --action_env=NIX_REMOTE=daemon
build --action_env=NIX_SSL_CERT_FILE

# =============================================================================
# Remote Cache Configuration
# =============================================================================

# Cluster-internal cache (GitLab runners, internal CI)
build:ci-internal --remote_cache=grpc://bazel-cache.attic-cache.svc.cluster.local:9092
build:ci-internal --remote_upload_local_results=true
build:ci-internal --remote_download_minimal

# External cache (developer workstations with VPN)
build:remote --remote_cache=grpcs://bazel-cache.prod-cluster.example.com:443
build:remote --remote_upload_local_results=true
build:remote --remote_download_minimal

# Local disk cache (fallback when remote unavailable)
build --disk_cache=~/.cache/bazel/attic-cache

# Async uploads for better performance
build --experimental_remote_cache_async

# Guard against concurrent modifications
build --experimental_guard_against_concurrent_changes

# =============================================================================
# Test Settings
# =============================================================================

test --test_output=errors
test --test_verbose_timeout_warnings

# =============================================================================
# Release/CI Configurations
# =============================================================================

# Release builds with stamping
build:release --stamp
build:release --workspace_status_command=./build/workspace_status.sh

# CI configuration (parallel jobs, no local cache)
build:ci --jobs=4
build:ci --disk_cache=
build:ci --color=yes
build:ci --curses=no
build:ci --config=ci-internal
test:ci --test_output=all

# =============================================================================
# Memory Optimization
# =============================================================================

startup --host_jvm_args=-Xmx4g

# =============================================================================
# User-specific Overrides
# =============================================================================

try-import %workspace%/user.bazelrc
```

### 3.3 Exposing Nix Packages as Bazel Targets

Create a `WORKSPACE.bzlmod` file for additional Nix package definitions:

```python
"""WORKSPACE.bzlmod - Additional Nix package definitions

This file defines nixpkgs_package rules that expose Nix packages as
Bazel targets. These complement the toolchain configurations in MODULE.bazel.
"""

load("@rules_nixpkgs_core//nixpkgs:nixpkgs.bzl", "nixpkgs_package")

# =============================================================================
# Development Tools
# =============================================================================

nixpkgs_package(
    name = "opentofu",
    repository = "@nixpkgs",
    attribute_path = "opentofu",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "bin",
    srcs = ["bin/tofu"],
)

sh_binary(
    name = "tofu",
    srcs = ["bin/tofu"],
)
""",
)

nixpkgs_package(
    name = "kubectl",
    repository = "@nixpkgs",
    attribute_path = "kubectl",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "bin",
    srcs = ["bin/kubectl"],
)

sh_binary(
    name = "kubectl",
    srcs = ["bin/kubectl"],
)
""",
)

nixpkgs_package(
    name = "jq",
    repository = "@nixpkgs",
    attribute_path = "jq",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "bin",
    srcs = ["bin/jq"],
)

sh_binary(
    name = "jq",
    srcs = ["bin/jq"],
)
""",
)

nixpkgs_package(
    name = "yq",
    repository = "@nixpkgs",
    attribute_path = "yq-go",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "bin",
    srcs = ["bin/yq"],
)

sh_binary(
    name = "yq",
    srcs = ["bin/yq"],
)
""",
)

# =============================================================================
# Nix Tools (for CI pushing to Attic)
# =============================================================================

nixpkgs_package(
    name = "nix",
    repository = "@nixpkgs",
    attribute_path = "nix",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "bin",
    srcs = glob(["bin/*"]),
)

sh_binary(
    name = "nix",
    srcs = ["bin/nix"],
)

sh_binary(
    name = "nix-build",
    srcs = ["bin/nix-build"],
)
""",
)
```

### 3.4 Flake Integration via nixpkgs_flake_package

For advanced integration, use the project's own flake outputs:

```python
# In WORKSPACE.bzlmod
load("@rules_nixpkgs_core//nixpkgs:nixpkgs.bzl", "nixpkgs_flake_package")

# Use packages defined in the project's flake.nix
nixpkgs_flake_package(
    name = "attic-client",
    flake = "//:flake.nix",
    package = "attic-client",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "bin",
    srcs = glob(["bin/*"]),
)

sh_binary(
    name = "attic",
    srcs = ["bin/attic"],
)
""",
)

nixpkgs_flake_package(
    name = "devshell",
    flake = "//:flake.nix",
    package = "devShells.default",
    # Inherit the entire dev shell for tests
)
```

---

## 4. Example Project Setup

### 4.1 Using Bazel for OpenTofu Validation

Create custom rules for OpenTofu validation in `build/tofu.bzl`:

```python
"""build/tofu.bzl - OpenTofu validation rules for Bazel"""

def _tofu_fmt_test_impl(ctx):
    """Implementation of tofu_fmt_test rule."""
    script = ctx.actions.declare_file(ctx.label.name + ".sh")

    script_content = """#!/bin/bash
set -euo pipefail

TOFU="${TOFU:-tofu}"

for dir in "$@"; do
    if [ -d "$dir" ]; then
        echo "Checking formatting in $dir..."
        if ! "$TOFU" fmt -check -recursive "$dir"; then
            echo "ERROR: OpenTofu files in $dir are not formatted"
            echo "Run: tofu fmt -recursive $dir"
            exit 1
        fi
    fi
done

echo "All OpenTofu files are properly formatted"
"""

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = ctx.files.srcs)

    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

tofu_fmt_test = rule(
    implementation = _tofu_fmt_test_impl,
    test = True,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "OpenTofu module directories to check",
        ),
    },
    doc = "Test that OpenTofu files are properly formatted",
)

def _tofu_validate_test_impl(ctx):
    """Implementation of tofu_validate_test rule."""
    script = ctx.actions.declare_file(ctx.label.name + ".sh")

    script_content = """#!/bin/bash
set -euo pipefail

TOFU="${TOFU:-tofu}"
MODULE_DIR="$1"

echo "Validating OpenTofu module in $MODULE_DIR..."

cd "$MODULE_DIR"

# Initialize without backend
"$TOFU" init -backend=false -input=false

# Validate
if ! "$TOFU" validate; then
    echo "ERROR: OpenTofu validation failed for $MODULE_DIR"
    exit 1
fi

echo "OpenTofu module $MODULE_DIR is valid"
"""

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = ctx.files.srcs)

    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

tofu_validate_test = rule(
    implementation = _tofu_validate_test_impl,
    test = True,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "OpenTofu module files",
        ),
        "module_dir": attr.string(
            mandatory = True,
            doc = "Path to the OpenTofu module directory",
        ),
    },
    doc = "Test that an OpenTofu module is valid",
)
```

### 4.2 BUILD.bazel for OpenTofu Modules

Update `tofu/modules/BUILD.bazel`:

```python
# tofu/modules/BUILD.bazel - OpenTofu module validation

load("//build:tofu.bzl", "tofu_fmt_test", "tofu_validate_test")

package(default_visibility = ["//visibility:public"])

# =============================================================================
# File Groups
# =============================================================================

filegroup(
    name = "all_modules",
    srcs = glob([
        "**/*.tf",
        "**/*.tfvars",
    ]),
)

# =============================================================================
# Format Tests
# =============================================================================

tofu_fmt_test(
    name = "fmt_test",
    srcs = [":all_modules"],
    tags = ["tofu", "lint"],
)

# =============================================================================
# Module Validation Tests
# =============================================================================

[
    tofu_validate_test(
        name = "{}_validate".format(module),
        srcs = glob(["{}/**/*.tf".format(module)]),
        module_dir = "tofu/modules/{}".format(module),
        tags = ["tofu", "validate"],
    )
    for module in [
        "bazel-cache",
        "cnpg-operator",
        "dns-record",
        "gitlab-runner",
        "hpa-deployment",
        "minio-operator",
        "minio-tenant",
        "postgresql-cnpg",
    ]
]

# =============================================================================
# Test Suite
# =============================================================================

test_suite(
    name = "all_module_tests",
    tests = [
        ":fmt_test",
    ] + [":{}_validate".format(m) for m in [
        "bazel-cache",
        "cnpg-operator",
        "dns-record",
        "gitlab-runner",
        "hpa-deployment",
        "minio-operator",
        "minio-tenant",
        "postgresql-cnpg",
    ]],
)
```

### 4.3 GitLab CI Integration

Update `.gitlab/ci/jobs/bazel-build.gitlab-ci.yml`:

```yaml
# Bazel Build Jobs with Remote Cache
# ===================================

.bazel-base:
  stage: build
  image: alpine:3.21
  tags:
    - nix
  interruptible: true
  variables:
    NIX_CONFIG: "experimental-features = nix-command flakes"
  cache:
    key: bazel-${CI_COMMIT_REF_SLUG}
    paths:
      - ~/.cache/bazel/
  before_script:
    - apk add --no-cache curl xz bash git
    - chmod 755 /nix 2>/dev/null || true
    - curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm --init none
    - . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    - nix develop --command bazel version
    # Use CI configuration with remote cache
    - echo "build --config=ci" >> user.bazelrc
    - echo "build --config=ci-internal" >> user.bazelrc

# =============================================================================
# Validation Jobs
# =============================================================================

bazel:validate:
  extends: .bazel-base
  stage: validate
  script:
    - echo "Validating Bazel configuration..."
    - nix develop --command bazel info
    - nix develop --command bazel query //...
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

bazel:format:
  extends: .bazel-base
  stage: validate
  script:
    - echo "Checking Bazel file formatting..."
    - nix develop --command buildifier -mode=check -r .
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

# =============================================================================
# Build Jobs
# =============================================================================

bazel:build:
  extends: .bazel-base
  script:
    - echo "Building Bazel targets (with remote cache)..."
    - nix develop --command bazel build //...
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  artifacts:
    paths:
      - bazel-bin/
    expire_in: 1 day

# =============================================================================
# Test Jobs
# =============================================================================

bazel:test:
  extends: .bazel-base
  stage: test
  script:
    - echo "Running Bazel tests..."
    - nix develop --command bazel test //... --test_output=all
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

# =============================================================================
# OpenTofu Validation via Bazel
# =============================================================================

bazel:tofu-validate:
  extends: .bazel-base
  stage: validate
  script:
    - echo "Validating OpenTofu modules via Bazel..."
    - nix develop --command bazel test //tofu/modules:all_module_tests --test_output=all
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        - tofu/modules/**/*.tf
```

---

## 5. Remote Execution Considerations

### 5.1 When to Add BuildBuddy/Buildbarn

Remote execution provides additional benefits beyond caching but adds significant complexity:

| Criteria                  | Cache-Only | Full RBE           |
| ------------------------- | ---------- | ------------------ |
| Build time improvement    | 50-80%     | 80-95%             |
| Infrastructure complexity | Low        | High               |
| Operations overhead       | 1 hr/week  | 4-8 hrs/week       |
| Resource requirements     | 2 CPU, 4Gi | 12-18 CPU, 40-50Gi |
| Nix compatibility         | Full       | Experimental       |

**Add remote execution when:**

1. Cache hit rate plateaus below 70%
2. Local resource constraints limit parallelism
3. CI queue times exceed 10 minutes
4. Multiple architectures (aarch64) needed regularly

### 5.2 Worker Configuration for Nix-Aware Execution

If remote execution becomes necessary, workers need `/nix/store` access:

```yaml
# Worker pod spec for Nix-aware execution
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: worker
      image: buchgr/bazel-remote-execution:latest
      volumeMounts:
        - name: nix-store
          mountPath: /nix/store
          readOnly: true
        - name: nix-var
          mountPath: /nix/var/nix
          readOnly: true
  volumes:
    - name: nix-store
      nfs:
        server: nfs.internal.example.com
        path: /exports/nix-store
    - name: nix-var
      nfs:
        server: nfs.internal.example.com
        path: /exports/nix-var
```

### 5.3 Alternative: NFS Mount Pattern

For environments with NFS:

```hcl
# In bazel-cache module, add NFS volume option
variable "enable_nix_store_mount" {
  description = "Mount /nix/store via NFS for remote execution compatibility"
  type        = bool
  default     = false
}

variable "nix_store_nfs_server" {
  description = "NFS server for /nix/store"
  type        = string
  default     = ""
}

variable "nix_store_nfs_path" {
  description = "NFS export path for /nix/store"
  type        = string
  default     = "/exports/nix-store"
}
```

---

## 6. Implementation Roadmap

### Phase 1: bazel-cache Module (1-2 weeks)

- [ ] Create `tofu/modules/bazel-cache/` module
- [ ] Add S3 credentials secret to MinIO tenant
- [ ] Create `bazel-cache` bucket in MinIO
- [ ] Deploy to dev-cluster cluster
- [ ] Update `.bazelrc` with remote cache config
- [ ] Test with GitLab CI

### Phase 2: rules_nixpkgs Integration (2-3 weeks)

- [ ] Update `MODULE.bazel` with toolchain configs
- [ ] Create `WORKSPACE.bzlmod` for package definitions
- [ ] Update `.bazelrc` for platform configuration
- [ ] Test toolchain resolution
- [ ] Document usage for developers

### Phase 3: OpenTofu Rules (1 week)

- [ ] Create `build/tofu.bzl` rules
- [ ] Update `tofu/modules/BUILD.bazel`
- [ ] Integrate with GitLab CI
- [ ] Validate all existing modules

### Phase 4: Production Deployment (1 week)

- [ ] Deploy bazel-cache to prod-cluster cluster
- [ ] Configure external Ingress
- [ ] Set up monitoring dashboards
- [ ] Create developer documentation
- [ ] Onboard pilot projects

---

## References

### Bazel Resources

- [bazel-remote GitHub](https://github.com/buchgr/bazel-remote) - Cache server documentation
- [Bazel Remote Caching](https://bazel.build/remote/caching) - Official Bazel docs
- [bazel-remote Helm Chart](https://artifacthub.io/packages/helm/slamdev/bazel-remote) - Helm deployment

### rules_nixpkgs Resources

- [rules_nixpkgs GitHub](https://github.com/tweag/rules_nixpkgs) - Tweag's integration rules
- [Bazel Central Registry](https://registry.bazel.build/modules/rules_nixpkgs_core) - Bzlmod packages
- [EngFlow Bzlmod Migration](https://blog.engflow.com/2025/01/16/migrating-to-bazel-modules-aka-bzlmod---module-extensions/index.html) - Migration guide

### Integration Patterns

- [Tweag: Bazel + Nix](https://www.tweag.io/blog/2022-12-15-bazel-nix-migration-experience/) - Migration experience
- [nix-bazel.build](https://nix-bazel.build/) - Community guide
- [HDL Factory rules_nixpkgs](https://www.hdlfactory.com/post/2025/04/11/rules_nixpkgs-use/) - Practical usage
