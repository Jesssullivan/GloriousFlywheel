output "namespace" {
  description = "Namespace where runner is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.gitlab_runner.name
}

output "chart_version" {
  description = "Deployed chart version"
  value       = helm_release.gitlab_runner.version
}
