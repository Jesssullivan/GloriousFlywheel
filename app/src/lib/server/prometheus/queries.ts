// Prebuilt PromQL queries matching tofu/modules/gitlab-runner/monitoring.tf
// These reference the exact metric names and labels from the GitLab Runner Prometheus exporter

import { env } from '$env/dynamic/private';

const NS = env.RUNNER_NAMESPACE ?? 'gitlab-runners';

export const QUERIES = {
  // Total jobs processed
  totalJobs: (runner?: string) =>
    runner
      ? `sum(gitlab_runner_jobs_total{namespace="${NS}", runner="${runner}"})`
      : `sum(gitlab_runner_jobs_total{namespace="${NS}"})`,

  // Failed jobs
  failedJobs: (runner?: string) =>
    runner
      ? `sum(gitlab_runner_failed_jobs_total{namespace="${NS}", runner="${runner}"})`
      : `sum(gitlab_runner_failed_jobs_total{namespace="${NS}"})`,

  // Success rate (over time window)
  successRate: (window: string = "1h") =>
    `1 - (sum(rate(gitlab_runner_failed_jobs_total{namespace="${NS}"}[${window}])) / sum(rate(gitlab_runner_jobs_total{namespace="${NS}"}[${window}])))`,

  // Jobs per minute (rate)
  jobsPerMinute: (runner?: string, window: string = "5m") =>
    runner
      ? `sum(rate(gitlab_runner_jobs_total{namespace="${NS}", runner="${runner}"}[${window}])) * 60`
      : `sum(rate(gitlab_runner_jobs_total{namespace="${NS}"}[${window}])) * 60`,

  // CPU usage by pod
  cpuUsage: (runner?: string) =>
    runner
      ? `sum(rate(container_cpu_usage_seconds_total{namespace="${NS}", pod=~"${runner}.*"}[5m])) by (pod)`
      : `sum(rate(container_cpu_usage_seconds_total{namespace="${NS}"}[5m])) by (pod)`,

  // Memory usage by pod
  memoryUsage: (runner?: string) =>
    runner
      ? `sum(container_memory_usage_bytes{namespace="${NS}", pod=~"${runner}.*"}) by (pod)`
      : `sum(container_memory_usage_bytes{namespace="${NS}"}[5m]) by (pod)`,

  // HPA current replicas
  hpaCurrentReplicas: (runner?: string) =>
    runner
      ? `kube_horizontalpodautoscaler_status_current_replicas{namespace="${NS}", horizontalpodautoscaler=~"${runner}.*"}`
      : `kube_horizontalpodautoscaler_status_current_replicas{namespace="${NS}"}`,

  // HPA desired replicas
  hpaDesiredReplicas: (runner?: string) =>
    runner
      ? `kube_horizontalpodautoscaler_status_desired_replicas{namespace="${NS}", horizontalpodautoscaler=~"${runner}.*"}`
      : `kube_horizontalpodautoscaler_status_desired_replicas{namespace="${NS}"}`,

  // Active alerts
  activeAlerts: () => `ALERTS{namespace="${NS}", alertstate="firing"}`,

  // Enrollment metrics
  quotaUsage: (resource: string) =>
    `kube_resourcequota{namespace="${NS}", resource="${resource}", type="used"} / kube_resourcequota{namespace="${NS}", resource="${resource}", type="hard"}`,

  pendingJobs: () =>
    `sum(gitlab_runner_jobs{state="pending", namespace="${NS}"}) or vector(0)`,

  orphanedNamespaces: () =>
    `count(kube_namespace_labels{namespace=~"ci-job-.*"}) - count(kube_pod_info{namespace=~"ci-job-.*"}) or vector(0)`,

  // Recording rule references (pre-computed)
  recordedJobsPerMinute: (runner?: string) =>
    runner
      ? `org:runner_jobs_per_minute:rate5m{runner="${runner}"}`
      : `sum(org:runner_jobs_per_minute:rate5m)`,

  recordedSuccessRate: (runner?: string) =>
    runner
      ? `org:runner_success_rate:rate1h{runner="${runner}"}`
      : `avg(org:runner_success_rate:rate1h)`,

  hpaUtilization: (runner?: string) =>
    runner
      ? `org:runner_hpa_utilization{runner="${runner}"}`
      : `avg(org:runner_hpa_utilization)`,
} as const;

// Time window presets (in seconds)
export const TIME_WINDOWS = {
  "1h": { seconds: 3600, step: "30s", label: "1 Hour" },
  "6h": { seconds: 21600, step: "120s", label: "6 Hours" },
  "24h": { seconds: 86400, step: "300s", label: "24 Hours" },
  "7d": { seconds: 604800, step: "1800s", label: "7 Days" },
} as const;

export type TimeWindow = keyof typeof TIME_WINDOWS;
