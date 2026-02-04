# GitLab Managed Terraform State
#
# State is stored in GitLab's built-in Terraform state management.
# Access via CI_JOB_TOKEN in pipelines.

terraform {
  backend "http" {}
}
