# HPA-Enabled Deployment Module - HPA-specific resources
#
# This file contains HPA-related resources and documentation.
# The main HPA resource is defined in main.tf for consistency.

# =============================================================================
# HPA Scaling Behavior Documentation
# =============================================================================
#
# Default HPA Behavior:
#   Scale Up:
#     - Stabilization: 0 seconds (immediate scale up)
#     - Max 100% increase OR 4 pods per 15-second period
#   Scale Down:
#     - Stabilization: 300 seconds (5 minutes)
#     - Max 10% decrease OR 2 pods per 60-second period
#
# This asymmetric behavior:
#   - Allows fast response to traffic spikes
#   - Prevents thrashing during normal load variations
#   - Maintains service availability during planned scale-downs
#
# Tuning Guidelines:
#   For cache services (Attic, Pulp):
#     - cpu_target_percent = 70
#     - memory_target_percent = 80
#     - scale_up_pods = 4 (fast response to cache miss storms)
#
#   For registries (Quay):
#     - cpu_target_percent = 60
#     - memory_target_percent = 70
#     - scale_down_stabilization_seconds = 600 (10 min for image pulls)
#
#   For mirrors (DNF, APT):
#     - cpu_target_percent = 80
#     - memory_target_percent = 85
#     - scale_up_percent = 200 (handle burst mirror syncs)
#
# =============================================================================
# Custom Metrics Integration
# =============================================================================
#
# To use custom metrics (e.g., requests per second):
#
# 1. Deploy metrics-server or prometheus-adapter
# 2. Define custom metric in HPA:
#
#   custom_metrics = [
#     {
#       name         = "http_requests_per_second"
#       target_value = "100"
#     }
#   ]
#
# 3. Ensure your application exposes the metric at /metrics
#
# Example Prometheus adapter config for Attic:
#   rules:
#     - seriesQuery: 'http_requests_total{namespace!="",pod!=""}'
#       resources:
#         overrides:
#           namespace: {resource: "namespace"}
#           pod: {resource: "pod"}
#       name:
#         matches: "^(.*)_total$"
#         as: "${1}_per_second"
#       metricsQuery: 'rate(<<.Series>>{<<.LabelMatchers>>}[2m])'
