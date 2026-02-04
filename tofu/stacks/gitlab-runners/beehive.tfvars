# Beehive Cluster - GitLab Runners Configuration

cluster_context = "bates-ils/projects/kubernetes/gitlab-agents:beehive"
namespace       = "gitlab-runners"
gitlab_url      = "https://gitlab.com"

deploy_k8s_runner   = true
nix_concurrent_jobs = 4
k8s_concurrent_jobs = 4

nix_cpu_request    = "100m"
nix_memory_request = "128Mi"
