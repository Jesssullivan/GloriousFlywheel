variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "runner_token" {
  description = "Runner authentication token (from GitLab UI or API)"
  type        = string
  sensitive   = true
}

variable "runner_name" {
  description = "Name for the runner Helm release"
  type        = string
}

variable "runner_tags" {
  description = "Tags for the runner"
  type        = list(string)
  default     = []
}

variable "namespace" {
  description = "Kubernetes namespace for runner"
  type        = string
  default     = "gitlab-runners"
}

variable "create_namespace" {
  description = "Create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "GitLab Runner Helm chart version"
  type        = string
  default     = "0.71.0"
}

variable "privileged" {
  description = "Run containers in privileged mode (required for DinD)"
  type        = bool
  default     = false
}

variable "concurrent_jobs" {
  description = "Maximum concurrent jobs"
  type        = number
  default     = 4
}

variable "cpu_request" {
  description = "CPU request for runner manager pod"
  type        = string
  default     = "100m"
}

variable "memory_request" {
  description = "Memory request for runner manager pod"
  type        = string
  default     = "128Mi"
}

variable "rbac_create" {
  description = "Create RBAC resources"
  type        = bool
  default     = true
}

variable "cluster_wide_access" {
  description = "Allow cluster-wide access (for deploying to any namespace)"
  type        = bool
  default     = false
}

variable "additional_values" {
  description = "Additional Helm values in YAML format"
  type        = string
  default     = ""
}
