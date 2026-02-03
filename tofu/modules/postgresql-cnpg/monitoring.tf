# CloudNativePG PostgreSQL - Monitoring Resources
#
# Prometheus ServiceMonitor and custom metrics configuration.

# =============================================================================
# ServiceMonitor for Prometheus Operator
# =============================================================================

resource "kubectl_manifest" "service_monitor" {
  count = var.enable_monitoring && var.create_service_monitor ? 1 : 0

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
        matchLabels = {
          "cnpg.io/cluster" = var.name
        }
      }
      endpoints = [
        {
          port     = "metrics"
          interval = var.metrics_scrape_interval
          path     = "/metrics"
        }
      ]
      namespaceSelector = {
        matchNames = [var.namespace]
      }
    }
  })

  depends_on = [kubectl_manifest.cluster]
}

# =============================================================================
# PrometheusRule for Alerts
# =============================================================================

resource "kubectl_manifest" "prometheus_rules" {
  count = var.enable_monitoring && var.create_prometheus_rules ? 1 : 0

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
              alert = "PostgreSQLDown"
              expr  = "cnpg_collector_up{cluster=\"${var.name}\"} == 0"
              for   = "5m"
              labels = {
                severity = "critical"
                cluster  = var.name
              }
              annotations = {
                summary     = "PostgreSQL cluster ${var.name} is down"
                description = "PostgreSQL cluster ${var.name} in namespace ${var.namespace} has been unreachable for more than 5 minutes."
              }
            },
            {
              alert = "PostgreSQLReplicationLag"
              expr  = "cnpg_pg_replication_lag{cluster=\"${var.name}\"} > ${var.alert_replication_lag_threshold}"
              for   = "5m"
              labels = {
                severity = "warning"
                cluster  = var.name
              }
              annotations = {
                summary     = "PostgreSQL replication lag is high"
                description = "PostgreSQL cluster ${var.name} has replication lag > ${var.alert_replication_lag_threshold} seconds for more than 5 minutes."
              }
            },
            {
              alert = "PostgreSQLHighConnections"
              expr  = "(cnpg_backends_total{cluster=\"${var.name}\"} / cnpg_pg_settings_setting{name=\"max_connections\",cluster=\"${var.name}\"}) > ${var.alert_connection_threshold}"
              for   = "5m"
              labels = {
                severity = "warning"
                cluster  = var.name
              }
              annotations = {
                summary     = "PostgreSQL connection usage is high"
                description = "PostgreSQL cluster ${var.name} is using more than ${var.alert_connection_threshold * 100}% of max_connections."
              }
            },
            {
              alert = "PostgreSQLDeadlocks"
              expr  = "increase(cnpg_pg_stat_database_deadlocks{cluster=\"${var.name}\"}[5m]) > ${var.alert_deadlock_threshold}"
              for   = "5m"
              labels = {
                severity = "warning"
                cluster  = var.name
              }
              annotations = {
                summary     = "PostgreSQL deadlocks detected"
                description = "PostgreSQL cluster ${var.name} has had more than ${var.alert_deadlock_threshold} deadlocks in the last 5 minutes."
              }
            },
            {
              alert = "PostgreSQLBackupFailed"
              expr  = "cnpg_pg_wal_archive_status{cluster=\"${var.name}\",status=\"failed\"} > 0"
              for   = "15m"
              labels = {
                severity = "critical"
                cluster  = var.name
              }
              annotations = {
                summary     = "PostgreSQL WAL archiving failed"
                description = "PostgreSQL cluster ${var.name} has failed WAL archives for more than 15 minutes. Backups may be affected."
              }
            },
            {
              alert = "PostgreSQLDiskSpaceLow"
              expr  = "(cnpg_pg_database_size_bytes{cluster=\"${var.name}\"} / (${parseint(replace(var.storage_size, "Gi", ""), 10)} * 1024 * 1024 * 1024)) > ${var.alert_disk_threshold}"
              for   = "30m"
              labels = {
                severity = "warning"
                cluster  = var.name
              }
              annotations = {
                summary     = "PostgreSQL disk space is low"
                description = "PostgreSQL cluster ${var.name} is using more than ${var.alert_disk_threshold * 100}% of allocated storage."
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.cluster]
}

# =============================================================================
# Custom Metrics ConfigMap
# =============================================================================

resource "kubernetes_config_map" "custom_queries" {
  count = var.enable_monitoring && length(var.custom_queries) > 0 ? 1 : 0

  metadata {
    name      = "${var.name}-custom-queries"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    queries = yamlencode(var.custom_queries)
  }
}

# =============================================================================
# Monitoring Variables
# =============================================================================

variable "create_service_monitor" {
  description = "Create ServiceMonitor for Prometheus Operator"
  type        = bool
  default     = false
}

variable "create_prometheus_rules" {
  description = "Create PrometheusRule for alerting"
  type        = bool
  default     = false
}

variable "prometheus_release_label" {
  description = "Label value for prometheus selector (e.g., 'kube-prometheus-stack')"
  type        = string
  default     = "prometheus"
}

variable "metrics_scrape_interval" {
  description = "Prometheus scrape interval"
  type        = string
  default     = "30s"
}

variable "custom_queries" {
  description = "Custom Prometheus queries for PostgreSQL metrics"
  type        = any
  default     = []
}

# Alert thresholds
variable "alert_replication_lag_threshold" {
  description = "Replication lag threshold in seconds for alerting"
  type        = number
  default     = 30
}

variable "alert_connection_threshold" {
  description = "Connection usage threshold (0-1) for alerting"
  type        = number
  default     = 0.8
}

variable "alert_deadlock_threshold" {
  description = "Deadlock count threshold for alerting"
  type        = number
  default     = 5
}

variable "alert_disk_threshold" {
  description = "Disk usage threshold (0-1) for alerting"
  type        = number
  default     = 0.85
}
