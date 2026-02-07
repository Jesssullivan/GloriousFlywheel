# Beehive Cluster - Bates ILS Runners Configuration
#
# Development environment configuration for the bates-ils group runners.
# Runners are registered at GROUP level for all bates-ils projects.

cluster_context = "bates-ils/projects/kubernetes/gitlab-agents:beehive"
namespace       = "bates-ils-runners"
gitlab_url      = "https://gitlab.com"

# =============================================================================
# Runner Deployment Toggles
# =============================================================================
# Set to false to skip deploying specific runner types

deploy_docker_runner = true
deploy_dind_runner   = true
deploy_rocky8_runner = true
deploy_rocky9_runner = true
deploy_nix_runner    = true

# =============================================================================
# Concurrency Settings
# =============================================================================
# Max concurrent jobs per runner manager pod

docker_concurrent_jobs = 8
dind_concurrent_jobs   = 4
rocky8_concurrent_jobs = 4
rocky9_concurrent_jobs = 4
nix_concurrent_jobs    = 4

# =============================================================================
# HPA Configuration
# =============================================================================

hpa_enabled           = true
hpa_cpu_target        = 70
hpa_memory_target     = 80
hpa_scale_up_window   = 15
hpa_scale_down_window = 300

# Per-runner scaling limits
docker_hpa_min_replicas = 1
docker_hpa_max_replicas = 5

dind_hpa_min_replicas = 1
dind_hpa_max_replicas = 3

rocky_hpa_min_replicas = 1
rocky_hpa_max_replicas = 3

nix_hpa_min_replicas = 1
nix_hpa_max_replicas = 3

# =============================================================================
# Pod Disruption Budget
# =============================================================================

pdb_enabled = true

# =============================================================================
# Attic Cache Integration (Nix Runner)
# =============================================================================

attic_server   = "https://attic-cache.beehive.bates.edu"
attic_cache    = "main"
nix_store_size = "20Gi"

# =============================================================================
# DinD Configuration
# =============================================================================

docker_version = "27-dind"

# Optional: Node selector for privileged DinD workloads
# dind_node_selector = {
#   "node.kubernetes.io/dind-enabled" = "true"
# }

# =============================================================================
# Monitoring
# =============================================================================

metrics_enabled         = true
service_monitor_enabled = true # Beehive has Prometheus Operator

service_monitor_labels = {
  "prometheus" = "kube-prometheus"
}

# =============================================================================
# Manager Pod Resources
# =============================================================================
# Resources for the runner manager pods (not job pods)

docker_cpu_request    = "25m"
docker_memory_request = "64Mi"
docker_cpu_limit      = "250m"
docker_memory_limit   = "256Mi"

dind_cpu_request    = "50m"
dind_memory_request = "64Mi"
dind_cpu_limit      = "250m"
dind_memory_limit   = "512Mi"

rocky_cpu_request    = "25m"
rocky_memory_request = "64Mi"
rocky_cpu_limit      = "250m"
rocky_memory_limit   = "256Mi"

nix_cpu_request    = "25m"
nix_memory_request = "64Mi"
nix_cpu_limit      = "250m"
nix_memory_limit   = "256Mi"

# =============================================================================
# Job Pod Resources
# =============================================================================
# Resources for the ephemeral job pods created for each CI job

docker_job_cpu_request    = "50m"
docker_job_memory_request = "128Mi"
docker_job_cpu_limit      = "2"
docker_job_memory_limit   = "2Gi"

dind_job_cpu_request    = "100m"
dind_job_memory_request = "256Mi"
dind_job_cpu_limit      = "4"
dind_job_memory_limit   = "8Gi"

rocky_job_cpu_request    = "50m"
rocky_job_memory_request = "128Mi"
rocky_job_cpu_limit      = "2"
rocky_job_memory_limit   = "2Gi"

nix_job_cpu_request    = "100m"
nix_job_memory_request = "256Mi"
nix_job_cpu_limit      = "4"
nix_job_memory_limit   = "8Gi"
