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
    l40s   = "nvidia/cuda:12.4-devel-ubuntu22.04"
    a100   = "nvidia/cuda:12.4-devel-ubuntu22.04"
  }

  # Whether runner type needs privileged mode
  runner_type_privileged = {
    docker = false
    dind   = true
    rocky8 = false
    rocky9 = false
    nix    = false
    l40s   = true
    a100   = true
  }

  # Whether runner type uses DinD service
  runner_type_dind = {
    docker = false
    dind   = true
    rocky8 = false
    rocky9 = false
    nix    = false
    l40s   = false
    a100   = false
  }

  # Default tags per runner type (merged with user tags)
  # NOTE: The "kubernetes" tag is intentionally EXCLUDED. Self-hosted runners
  # should only match jobs that explicitly request their workload type (docker,
  # nix, etc). Overlay CI pipelines use tags: [kubernetes] to target SaaS
  # shared runners for jobs that need internet access (e.g., cloning upstream
  # from GitHub). Including "kubernetes" here causes self-hosted runners on
  # restricted networks to grab those jobs and fail.
  # See: docs/runners/tag-strategy.md
  runner_type_default_tags = {
    docker = ["docker", "linux", "amd64"]
    dind   = ["docker", "dind", "privileged"]
    rocky8 = ["rocky8", "rhel8", "linux"]
    rocky9 = ["rocky9", "rhel9", "linux"]
    nix    = ["nix", "flakes"]
    l40s   = ["gpu", "nvidia", "cuda", "l40s", "linux"]
    a100   = ["gpu", "nvidia", "cuda", "a100", "linux"]
  }

  # Whether this runner type needs GPU resources
  gpu_enabled = contains(["l40s", "a100"], var.runner_type)

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

    # Nix store volume configuration (only when emptyDir is enabled)
    volumes = var.nix_store_emptydir ? [
      {
        name       = "nix-store"
        mount_path = "/nix"
        type       = "emptyDir"
        size_limit = var.nix_store_size
      }
    ] : []
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
  # Job Environment Variables
  # =============================================================================

  # Environment variables injected into CI job containers via [[runners]] environment
  runner_env_vars = concat(
    local.dind_enabled ? [
      "DOCKER_HOST=tcp://localhost:2375",
      "DOCKER_TLS_CERTDIR=",
    ] : [],
    var.runner_type == "nix" && var.attic_server != "" ? [
      "NIX_CONFIG=experimental-features = nix-command flakes",
      "ATTIC_SERVER=${var.attic_server}",
      "ATTIC_CACHE=${var.attic_cache}",
    ] : [],
    var.bazel_cache_endpoint != "" && contains(["docker", "nix"], var.runner_type) ? [
      "BAZEL_REMOTE_CACHE=${var.bazel_cache_endpoint}",
    ] : [],
    local.gpu_enabled ? [
      "NVIDIA_VISIBLE_DEVICES=all",
      "NVIDIA_DRIVER_CAPABILITIES=compute,utility",
    ] : [],
  )

  # =============================================================================
  # Kubernetes Runner Configuration (TOML)
  # =============================================================================

  # Build runner config TOML
  # Uses flat keys and environment list — nested TOML tables cause type
  # mismatches with GitLab Runner 17.x config parser.
  runner_config_toml = <<-TOML
    [[runners]]
      name = "${var.runner_name}"
      executor = "kubernetes"
      ${length(local.runner_env_vars) > 0 ? "environment = ${jsonencode(local.runner_env_vars)}" : ""}
      [runners.feature_flags]
        FF_USE_LEGACY_KUBERNETES_EXECUTION_STRATEGY = ${var.use_legacy_exec_strategy}
        FF_PRINT_POD_EVENTS = ${var.print_pod_events}
        FF_USE_POD_ACTIVE_DEADLINE_SECONDS = ${var.use_active_deadline}
        FF_CLEANUP_FAILED_CACHE_EXTRACT = ${var.cleanup_failed_cache_extract}
      [runners.kubernetes]
        namespace = "${var.namespace}"
        image = "${local.default_image}"
        privileged = ${local.privileged}
        poll_timeout = ${var.poll_timeout}
        poll_interval = ${var.poll_interval}
        %{if var.namespace_per_job~}
        namespace_per_job = true
        namespace_per_job_prefix = "${var.namespace_per_job_prefix}"
        %{endif~}
        %{if local.dind_enabled && var.dind_sidecar_in_toml~}
        # DinD service (--tls=false disables TLS in the daemon)
        # NOTE: Only enable if CI jobs do NOT define their own DinD service.
        # Duplicate DinD services cause port 2375 conflicts.
        [[runners.kubernetes.services]]
          name = "docker"
          alias = "docker"
          image = "docker:${var.docker_version}"
          command = ["--storage-driver=overlay2", "--tls=false"]
        %{endif~}
        %{if var.runner_type == "nix" && var.nix_store_emptydir~}
        # Nix store volume (WARNING: shadows image /nix — use init container to preserve)
        [[runners.kubernetes.volumes.empty_dir]]
          name = "nix-store"
          mount_path = "/nix"
          medium = ""
          size_limit = "${var.nix_store_size}"
        %{endif~}
        # Job pod resources
        cpu_request = "${var.job_cpu_request}"
        memory_request = "${var.job_memory_request}"
        cpu_limit = "${var.job_cpu_limit}"
        memory_limit = "${var.job_memory_limit}"
        %{if var.job_priority_class_name != ""~}
        pod_priority_class_name = "${var.job_priority_class_name}"
        %{endif~}
        %{if var.cleanup_enabled~}
        pod_termination_grace_period_seconds = ${var.cleanup_grace_seconds}
        cleanup_grace_period_seconds = ${var.cleanup_grace_period_seconds}
        %{endif~}
        %{if local.gpu_enabled~}
        # GPU node selector
        %{for key, value in var.gpu_node_selector~}
        [runners.kubernetes.node_selector]
          ${key} = "${value}"
        %{endfor~}
        # GPU tolerations
        %{for toleration in var.gpu_tolerations~}
        [[runners.kubernetes.node_tolerations]]
          key = "${toleration.key}"
          operator = "${toleration.operator}"
          %{if toleration.value != null~}
          value = "${toleration.value}"
          %{endif~}
          effect = "${toleration.effect}"
        %{endfor~}
        # GPU resource request via pod_spec strategic merge patch
        pod_spec = ${jsonencode(jsonencode({
          containers = [{
            name = "build"
            resources = {
              requests = {
                (var.gpu_resource_name) = tostring(var.gpu_count)
              }
              limits = {
                (var.gpu_resource_name) = tostring(var.gpu_count)
              }
            }
          }]
        }))}
        %{endif~}
  TOML
}
