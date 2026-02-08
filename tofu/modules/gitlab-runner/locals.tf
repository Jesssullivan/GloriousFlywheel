# GitLab Runner Module - Local Variables
#
# Computed values based on runner type and configuration.

locals {
  # =============================================================================
  # Runner Type Defaults
  # =============================================================================

  # Default images per runner type
  runner_type_images = {
    docker = "alpine:3.21"
    dind   = "docker:${var.docker_version}"
    rocky8 = "rockylinux:8"
    rocky9 = "rockylinux:9"
    nix    = "docker.nix-community.org/nixpkgs/nix-flakes:nixos-unstable"
  }

  # Whether runner type needs privileged mode
  runner_type_privileged = {
    docker = false
    dind   = true
    rocky8 = false
    rocky9 = false
    nix    = false
  }

  # Whether runner type uses DinD service
  runner_type_dind = {
    docker = false
    dind   = true
    rocky8 = false
    rocky9 = false
    nix    = false
  }

  # Default tags per runner type (merged with user tags)
  runner_type_default_tags = {
    docker = ["docker", "linux", "amd64"]
    dind   = ["docker", "dind", "privileged"]
    rocky8 = ["rocky8", "rhel8", "linux"]
    rocky9 = ["rocky9", "rhel9", "linux"]
    nix    = ["nix", "flakes"]
  }

  # =============================================================================
  # Computed Values
  # =============================================================================

  # Effective default image
  default_image = var.default_image != "" ? var.default_image : local.runner_type_images[var.runner_type]

  # Effective privileged mode
  privileged = var.privileged != null ? var.privileged : local.runner_type_privileged[var.runner_type]

  # Effective DinD setting
  dind_enabled = var.dind_enabled != null ? var.dind_enabled : local.runner_type_dind[var.runner_type]

  # Merge user tags with runner type defaults (user tags take precedence)
  runner_tags = distinct(concat(
    local.runner_type_default_tags[var.runner_type],
    var.runner_tags
  ))

  # Service account name (default to runner name if not specified)
  service_account = var.service_account_name != "" ? var.service_account_name : var.runner_name

  # =============================================================================
  # Labels
  # =============================================================================

  common_labels = {
    "app.kubernetes.io/name"       = "gitlab-runner"
    "app.kubernetes.io/instance"   = var.runner_name
    "app.kubernetes.io/managed-by" = "opentofu"
    "app.kubernetes.io/component"  = "runner-manager"
    "app.kubernetes.io/runner-type" = var.runner_type
  }

  # =============================================================================
  # Nix Runner Configuration
  # =============================================================================

  nix_config = var.runner_type == "nix" ? {
    # Environment variables for Nix builds
    env_vars = concat(
      [
        { name = "NIX_CONFIG", value = "experimental-features = nix-command flakes" }
      ],
      var.attic_server != "" ? [
        { name = "ATTIC_SERVER", value = var.attic_server },
        { name = "ATTIC_CACHE", value = var.attic_cache }
      ] : []
    )

    # Nix store volume configuration
    volumes = [
      {
        name       = "nix-store"
        mount_path = "/nix"
        type       = "emptyDir"
        size_limit = var.nix_store_size
      }
    ]
  } : null

  # =============================================================================
  # DinD Runner Configuration
  # =============================================================================

  dind_config = local.dind_enabled ? {
    # DinD service container
    services = [
      {
        name  = "dind"
        alias = "docker"
        image = "docker:${var.docker_version}"
        command = [
          "--storage-driver=overlay2",
          "--tls=false"
        ]
        env = [
          { name = "DOCKER_TLS_CERTDIR", value = "" }
        ]
      }
    ]

    # Docker environment for job containers
    env_vars = [
      { name = "DOCKER_HOST", value = "tcp://localhost:2375" },
      { name = "DOCKER_TLS_CERTDIR", value = "" }
    ]
  } : null

  # =============================================================================
  # Kubernetes Runner Configuration (TOML)
  # =============================================================================

  # Build runner config TOML
  runner_config_toml = <<-TOML
    [[runners]]
      name = "${var.runner_name}"
      executor = "kubernetes"
      [runners.kubernetes]
        namespace = "${var.namespace}"
        image = "${local.default_image}"
        privileged = ${local.privileged}
        %{if var.namespace_per_job~}
        namespace_per_job = true
        namespace_per_job_prefix = "${var.namespace_per_job_prefix}"
        %{endif~}
        %{if local.dind_enabled~}
        # DinD service configuration
        [[runners.kubernetes.services]]
          name = "docker"
          alias = "docker"
          image = "docker:${var.docker_version}"
          command = ["--storage-driver=overlay2", "--tls=false"]
          [[runners.kubernetes.services.env]]
            name = "DOCKER_TLS_CERTDIR"
            value = ""
        %{endif~}
        %{if var.runner_type == "nix"~}
        # Nix store volume
        [[runners.kubernetes.volumes.empty_dir]]
          name = "nix-store"
          mount_path = "/nix"
          medium = ""
          size_limit = "${var.nix_store_size}"
        %{endif~}
        # Job pod resources
        [runners.kubernetes.cpu_request]
          value = "${var.job_cpu_request}"
        [runners.kubernetes.memory_request]
          value = "${var.job_memory_request}"
        [runners.kubernetes.cpu_limit]
          value = "${var.job_cpu_limit}"
        [runners.kubernetes.memory_limit]
          value = "${var.job_memory_limit}"
        %{if var.cleanup_enabled~}
        # Cleanup settings
        [runners.kubernetes.pod_termination_grace_period_seconds]
          value = ${var.cleanup_grace_seconds}
        %{endif~}
        %{if local.dind_enabled~}
        # DinD environment variables
        [[runners.kubernetes.pod_spec.containers]]
          name = "build"
          [[runners.kubernetes.pod_spec.containers.env]]
            name = "DOCKER_HOST"
            value = "tcp://localhost:2375"
          [[runners.kubernetes.pod_spec.containers.env]]
            name = "DOCKER_TLS_CERTDIR"
            value = ""
        %{endif~}
        %{if var.runner_type == "nix" && var.attic_server != ""~}
        # Attic cache environment
        [[runners.kubernetes.pod_spec.containers]]
          name = "build"
          [[runners.kubernetes.pod_spec.containers.env]]
            name = "NIX_CONFIG"
            value = "experimental-features = nix-command flakes"
          [[runners.kubernetes.pod_spec.containers.env]]
            name = "ATTIC_SERVER"
            value = "${var.attic_server}"
          [[runners.kubernetes.pod_spec.containers.env]]
            name = "ATTIC_CACHE"
            value = "${var.attic_cache}"
        %{endif~}
        %{if var.bazel_cache_endpoint != "" && contains(["docker", "nix"], var.runner_type)~}
        # Bazel remote cache
        [[runners.kubernetes.pod_spec.containers]]
          name = "build"
          [[runners.kubernetes.pod_spec.containers.env]]
            name = "BAZEL_REMOTE_CACHE"
            value = "${var.bazel_cache_endpoint}"
        %{endif~}
  TOML
}
