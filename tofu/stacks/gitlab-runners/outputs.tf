output "nix_runner_namespace" {
  description = "Namespace for Nix runner"
  value       = module.nix_runner.namespace
}

output "nix_runner_release" {
  description = "Nix runner Helm release name"
  value       = module.nix_runner.release_name
}

output "k8s_runner_release" {
  description = "K8s runner Helm release name"
  value       = var.deploy_k8s_runner ? module.k8s_runner[0].release_name : ""
}
