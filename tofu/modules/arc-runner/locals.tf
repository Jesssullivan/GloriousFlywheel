# ARC Runner Module - Local Variables
#
# Computed values based on runner type and configuration.

locals {
  # =============================================================================
  # Runner Type Defaults
  # =============================================================================

  # Default images per runner type
  # The runner image must include the GH Actions runner agent (/home/runner/run.sh).
  # For nix runners, we use a custom image with Nix + xz pre-installed so that
  # cachix/install-nix-action and nix-installer-action both work without extra deps.
  runner_type_images = {
    docker = "ghcr.io/actions/actions-runner:latest"
    dind   = "ghcr.io/actions/actions-runner:latest"
    nix    = "ghcr.io/actions/actions-runner:latest"
  }

  # Tool images used as init containers to provide tooling (Nix store, etc.)
  runner_tool_images = {
    nix = "docker.nix-community.org/nixpkgs/nix-flakes:nixos-unstable"
  }

  # Container mode per runner type
  runner_type_container_mode = {
    docker = "kubernetes"
    dind   = "dind"
    nix    = "kubernetes"
  }

  # =============================================================================
  # Computed Values
  # =============================================================================

  container_mode = var.container_mode != "" ? var.container_mode : local.runner_type_container_mode[var.runner_type]
  runner_image   = var.runner_image != "" ? var.runner_image : local.runner_type_images[var.runner_type]

  # =============================================================================
  # Environment Variables
  # =============================================================================

  # Cache environment variables injected into runner pods
  cache_env_vars = concat(
    var.runner_type == "nix" ? [
      { name = "NIX_CONFIG", value = "experimental-features = nix-command flakes" },
    ] : [],
    var.runner_type == "nix" && var.attic_server != "" ? [
      { name = "ATTIC_SERVER", value = var.attic_server },
      { name = "ATTIC_CACHE", value = var.attic_cache },
    ] : [],
    var.bazel_cache_endpoint != "" && contains(["docker", "nix"], var.runner_type) ? [
      { name = "BAZEL_REMOTE_CACHE", value = var.bazel_cache_endpoint },
    ] : [],
    local.container_mode == "dind" ? [
      { name = "DOCKER_HOST", value = "tcp://localhost:2375" },
      { name = "DOCKER_TLS_CERTDIR", value = "" },
    ] : [],
  )

  # Merge computed env vars with user-supplied extras
  all_env_vars = concat(local.cache_env_vars, var.env_vars)

  # =============================================================================
  # Labels
  # =============================================================================

  common_labels = {
    "app.kubernetes.io/name"        = "arc-runner"
    "app.kubernetes.io/instance"    = var.runner_name
    "app.kubernetes.io/managed-by"  = "opentofu"
    "app.kubernetes.io/component"   = "runner-scale-set"
    "app.kubernetes.io/runner-type" = var.runner_type
  }
}
