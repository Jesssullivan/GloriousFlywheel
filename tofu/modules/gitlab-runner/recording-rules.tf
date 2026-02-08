# GitLab Runner Module - Prometheus Recording Rules
#
# Pre-computed metrics for dashboard performance.

resource "kubernetes_manifest" "recording_rules" {
  count = var.service_monitor_enabled ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "${var.runner_name}-recording-rules"
      namespace = var.namespace
      labels = merge(local.common_labels, var.service_monitor_labels, {
        "app.kubernetes.io/component" = "recording-rules"
      })
    }

    spec = {
      groups = [
        {
          name     = "gitlab-runner-${var.runner_name}-recording"
          interval = "30s"

          rules = [
            {
              record = "${var.metric_prefix}:runner_jobs_per_minute:rate5m"
              expr   = "sum(rate(gitlab_runner_jobs_total{namespace=\"${var.namespace}\", runner=\"${var.runner_name}\"}[5m])) * 60"
              labels = {
                runner = var.runner_name
              }
            },
            {
              record = "${var.metric_prefix}:runner_success_rate:rate1h"
              expr   = "1 - (sum(rate(gitlab_runner_failed_jobs_total{namespace=\"${var.namespace}\", runner=\"${var.runner_name}\"}[1h])) / sum(rate(gitlab_runner_jobs_total{namespace=\"${var.namespace}\", runner=\"${var.runner_name}\"}[1h])))"
              labels = {
                runner = var.runner_name
              }
            },
            {
              record = "${var.metric_prefix}:runner_hpa_utilization"
              expr   = "kube_horizontalpodautoscaler_status_current_replicas{namespace=\"${var.namespace}\", horizontalpodautoscaler=\"${var.runner_name}-hpa\"} / kube_horizontalpodautoscaler_spec_max_replicas{namespace=\"${var.namespace}\", horizontalpodautoscaler=\"${var.runner_name}-hpa\"}"
              labels = {
                runner = var.runner_name
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.gitlab_runner]
}
