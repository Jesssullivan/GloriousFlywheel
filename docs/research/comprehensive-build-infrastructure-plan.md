# Comprehensive Build Infrastructure Plan

## IaC Monorepo - Full Stack Package Caching

**Date:** 2026-02-05
**Status:** Planning Phase
**Repository:** attic-cache (dogfood example)

---

## Executive Summary

This plan consolidates research from 4 parallel investigations to create a unified build infrastructure supporting:

| Ecosystem           | Solution               | Status  |
| ------------------- | ---------------------- | ------- |
| **Nix packages**    | Attic (deployed)       | Phase 1 |
| **Bazel actions**   | bazel-remote (planned) | Phase 2 |
| **RPM packages**    | Nexus or createrepo    | Phase 3 |
| **NuGet packages**  | BaGetter or GitLab     | Phase 3 |
| **Ansible content** | Galaxy NG (Pulp)       | Phase 3 |

**Key Answer: Yes, Attic can cache ALL standard Nix packages** - musl builds, web servers, flakes, devShells, cross-compiled binaries. Attic's chunk-level deduplication makes it especially efficient for variant builds (glibc/musl/static) that share common code.

---

## Part 1: Attic for Standard Nix Packages

### What Attic Can Cache

| Content Type      | Example                                 | Supported                 |
| ----------------- | --------------------------------------- | ------------------------- |
| Standard packages | nginx, postgresql, go                   | Yes                       |
| musl builds       | `pkgsStatic.hello`                      | Yes                       |
| Cross-compiled    | `pkgsCross.aarch64-multiplatform.hello` | Yes                       |
| devShells         | Development environments                | Yes (via inputDerivation) |
| Flake outputs     | packages, apps, checks                  | Yes                       |
| Container images  | nix2container outputs                   | Yes                       |

### musl/Static Build Example

```nix
# flake.nix
{
  packages.x86_64-linux = {
    # Standard glibc
    myapp = pkgs.myapp;

    # Static musl (single binary)
    myapp-static = pkgs.pkgsStatic.myapp;

    # Cross-compiled aarch64 static
    myapp-aarch64 = pkgs.pkgsCross.aarch64-multiplatform-musl.pkgsStatic.myapp;
  };
}
```

```bash
# Build and cache
nix build .#myapp-static --out-link result
attic push main result

# Verify static linking
file result/bin/myapp
# Output: ELF 64-bit LSB executable, statically linked
```

### devShell Caching

```nix
# Make devShell cacheable
packages.x86_64-linux.dev-shell =
  self.devShells.x86_64-linux.default.inputDerivation;
```

```bash
# Build and cache devShell dependencies
nix build .#dev-shell && attic push main result
```

### watch-store for Comprehensive Caching

```bash
# Cache ALL store paths created during a build
attic watch-store main &
nix build .#package
nix develop -c echo "Shell deps cached"
kill %1
```

### Recommended Cache Organization

```bash
# Multiple caches for different retention needs
attic cache create main --public              # General (90 days)
attic cache create ci --public                # CI builds (30 days)
attic cache create static --public            # musl/static (180 days)
attic cache create devshells --public         # Dev environments (60 days)
```

---

## Part 2: Bazel Remote Caching

### bazel-remote Module

New module at `tofu/modules/bazel-cache/` with:

| Component  | Description                           |
| ---------- | ------------------------------------- |
| Deployment | 2 replicas, gRPC (9092) + HTTP (8080) |
| Storage    | MinIO S3 backend (existing)           |
| HPA        | CPU/memory-based autoscaling          |
| Monitoring | Prometheus ServiceMonitor             |

**Resource Requirements:**

| Component         | CPU   | Memory |
| ----------------- | ----- | ------ |
| bazel-remote (x2) | 1 CPU | 2Gi    |
| **Total new**     | 2 CPU | 4Gi    |

### Client Configuration

```bash
# .bazelrc
build --remote_cache=grpc://bazel-cache.prod.example.com:9092
build --remote_upload_local_results=true
build --remote_download_minimal

# CI-specific
build:ci --remote_cache=grpc://bazel-cache.bazel-cache.svc.cluster.local:9092
```

### rules_nixpkgs Integration

```python
# MODULE.bazel
bazel_dep(name = "rules_nixpkgs_core", version = "0.13.0")
bazel_dep(name = "rules_nixpkgs_cc", version = "0.13.0")
```

```bash
# .bazelrc
common --host_platform=@rules_nixpkgs_core//platforms:host
common --incompatible_enable_cc_toolchain_resolution
```

**Supported Toolchains:** C/C++, Go, Python, Rust, Haskell, Node.js

---

## Part 3: RPM, NuGet, and Pulp Options

### Comparison Matrix

| Solution                    | RPM          | NuGet | Ansible | npm | PyPI | Resources    |
| --------------------------- | ------------ | ----- | ------- | --- | ---- | ------------ |
| **GitLab Package Registry** | Experimental | Yes   | No      | Yes | Yes  | 0 (existing) |
| **Nexus OSS**               | Yes          | Yes   | No      | Yes | Yes  | 2 CPU, 6Gi   |
| **Pulp 3**                  | Yes          | No    | Yes     | No  | Yes  | 3 CPU, 3Gi   |
| **BaGetter**                | No           | Yes   | No      | No  | No   | 500m, 512Mi  |

### Recommendations

1. **Start with GitLab Package Registry** - Already available, supports NuGet/npm/PyPI
2. **Add Nexus OSS** - If you need RPM or unified management
3. **Add Galaxy NG (Pulp)** - For Ansible collections/roles

### Nexus OSS Deployment

```hcl
# tofu/modules/nexus-repository/main.tf
resource "helm_release" "nexus" {
  name       = "nexus"
  repository = "https://sonatype.github.io/helm3-charts/"
  chart      = "nexus-repository-manager"
  namespace  = var.namespace

  set {
    name  = "persistence.storageClass"
    value = "longhorn"
  }

  set {
    name  = "nexus.resources.requests.memory"
    value = "4Gi"
  }
}
```

### Galaxy NG (Pulp) for Ansible

```hcl
# tofu/modules/galaxy-ng/main.tf
resource "helm_release" "galaxy_ng" {
  name       = "galaxy"
  repository = "https://pulp.github.io/pulp-operator"
  chart      = "pulp"
  namespace  = var.namespace

  values = [yamlencode({
    pulp_settings = {
      galaxy_enable_api_access_log = true
    }
    content_origin = "https://galaxy.prod.example.com"
  })]
}
```

---

## Part 4: IaC Monorepo Dogfooding

### attic-cache as Reference Implementation

This repository demonstrates:

```
attic-cache/                    # IaC Monorepo Example
├── MODULE.bazel                # Bzlmod dependencies
├── flake.nix                   # Nix tools + containers
├── .bazelrc                    # Bazel configuration
│
├── tofu/
│   ├── modules/                # Reusable OpenTofu modules
│   │   ├── BUILD.bazel         # Module validation targets
│   │   ├── bazel-cache/        # NEW: Bazel caching
│   │   ├── nexus-repository/   # NEW: RPM/NuGet
│   │   └── galaxy-ng/          # NEW: Ansible
│   └── stacks/
│       └── attic/              # Self-deploying infrastructure
│
├── build/                      # Custom Bazel rules
│   └── tofu/
│       └── rules.bzl           # tofu_validate, tofu_fmt
│
└── tests/                      # Validation tests
    └── BUILD.bazel
```

### OpenTofu Validation with Bazel

```python
# tofu/modules/BUILD.bazel
load("@rules_tf//tf:defs.bzl", "tf_module")

tf_module(
    name = "bazel_cache",
    srcs = glob(["bazel-cache/*.tf"]),
    providers = ["kubernetes", "helm"],
)

tf_module(
    name = "nexus_repository",
    srcs = glob(["nexus-repository/*.tf"]),
    providers = ["kubernetes", "helm"],
)
```

### Affected Target Analysis

```yaml
# .gitlab-ci.yml
bazel:affected:
  script:
    - |
      # Only validate changed modules
      target-determinator \
        -targets="//tofu/..." \
        origin/main HEAD > affected.txt

      if [ -s affected.txt ]; then
        bazel build $(cat affected.txt)
      fi
```

---

## Part 5: Implementation Phases

### Phase 1: Current (Attic Foundation)

**Status:** In Progress

- [x] Attic deployed on dev-cluster
- [x] MinIO storage configured
- [x] GitLab CI integration
- [ ] Production deployment (prod-cluster)
- [ ] Document musl/static caching patterns

**Deliverables:**

- Attic serving at `attic-cache.prod.example.com`
- Example flake.nix with static builds
- CI template for cache push

### Phase 2: Bazel Caching (Weeks 1-3)

**Goals:**

- Deploy bazel-remote with MinIO backend
- Integrate rules_nixpkgs for toolchains
- Add OpenTofu validation rules

**Tasks:**

| Task                                 | Effort | Priority |
| ------------------------------------ | ------ | -------- |
| Create `tofu/modules/bazel-cache/`   | 2 days | High     |
| Deploy bazel-remote to dev-cluster       | 1 day  | High     |
| Configure rules_nixpkgs CC toolchain | 1 day  | Medium   |
| Add BUILD.bazel to tofu/modules/     | 2 days | Medium   |
| Integrate with GitLab CI             | 1 day  | High     |

### Phase 3: Package Repositories (Weeks 4-6)

**Goals:**

- Evaluate GitLab Package Registry for NuGet
- Deploy Nexus OSS if needed
- Deploy Galaxy NG for Ansible

**Tasks:**

| Task                            | Effort | Priority |
| ------------------------------- | ------ | -------- |
| Test GitLab NuGet registry      | 1 day  | High     |
| Create Nexus module (if needed) | 2 days | Medium   |
| Create Galaxy NG module         | 2 days | Medium   |
| Document repository usage       | 1 day  | Medium   |

### Phase 4: Full Integration (Weeks 7-10)

**Goals:**

- Affected target analysis in CI
- Self-hosting validation (dogfood)
- Organization-wide documentation

**Tasks:**

| Task                             | Effort | Priority |
| -------------------------------- | ------ | -------- |
| Implement target-determinator    | 2 days | Medium   |
| Add rules_tf for tofu validation | 3 days | Medium   |
| Create user onboarding guide     | 2 days | High     |
| Performance benchmarking         | 1 day  | Low      |

---

## Part 6: Resource Summary

### Total New Infrastructure

| Component                | CPU   | Memory   | Storage  |
| ------------------------ | ----- | -------- | -------- |
| bazel-remote (x2)        | 2     | 4Gi      | MinIO    |
| Nexus OSS (optional)     | 2     | 6Gi      | 50Gi     |
| Galaxy NG (optional)     | 2     | 3Gi      | 20Gi     |
| **Minimum (Bazel only)** | **2** | **4Gi**  | **0**    |
| **Full stack**           | **6** | **13Gi** | **70Gi** |

### Storage Allocation (MinIO)

| Bucket       | Purpose          | Estimate  |
| ------------ | ---------------- | --------- |
| attic        | Nix NARs         | 300Gi     |
| bazel-cache  | Action cache     | 100Gi     |
| nexus-blobs  | RPM/NuGet        | 100Gi     |
| pulp-content | Ansible          | 50Gi      |
| pg-backup    | Database backups | 50Gi      |
| **Total**    |                  | **600Gi** |

Current MinIO: 800Gi (sufficient)

---

## Part 7: Quick Reference

### Cache URLs (Target State)

| Service              | URL                                       |
| -------------------- | ----------------------------------------- |
| Attic (Nix)          | `https://attic-cache.prod.example.com`     |
| bazel-remote         | `grpc://bazel-cache.prod.example.com:9092` |
| Nexus (optional)     | `https://nexus.prod.example.com`           |
| Galaxy NG (optional) | `https://galaxy.prod.example.com`          |

### Client Configuration

**Nix (nix.conf):**

```ini
substituters = https://attic-cache.prod.example.com/main https://cache.nixos.org
```

**Bazel (.bazelrc):**

```bash
build --remote_cache=grpc://bazel-cache.prod.example.com:9092
```

**NuGet (nuget.config):**

```xml
<add key="Internal" value="https://gitlab.com/api/v4/groups/GROUP_ID/-/packages/nuget/index.json" />
```

**Ansible (ansible.cfg):**

```ini
[galaxy]
server_list = org_galaxy, galaxy

[galaxy_server.org_galaxy]
url = https://galaxy.prod.example.com/api/
```

---

## Appendix A: Research Documents

| Document                                                                     | Content                            |
| ---------------------------------------------------------------------------- | ---------------------------------- |
| [campus-build-infrastructure.md](./campus-build-infrastructure.md)           | Overall strategy, ROI analysis     |
| [bazel-remote-nixpkgs-integration.md](./bazel-remote-nixpkgs-integration.md) | bazel-remote module, rules_nixpkgs |
| [package-repository-options.md](./package-repository-options.md)             | RPM, NuGet, Pulp comparison        |

---

## Appendix B: Decision Log

| Decision                      | Rationale                                |
| ----------------------------- | ---------------------------------------- |
| bazel-remote over BuildBuddy  | Simpler, cache-only sufficient initially |
| Separate Nix/Bazel caches     | Different caching models, can't share    |
| GitLab Package Registry first | Zero additional infrastructure           |
| Nexus over Artifactory        | Free, sufficient features                |
| Galaxy NG over AWX            | Focused on content, not execution        |
| Bzlmod over WORKSPACE         | Future-proof, WORKSPACE deprecated       |

---

## Appendix C: Related Projects

| Project        | Relevance                        |
| -------------- | -------------------------------- |
| example-project | Haskell/Python project using Nix |
| org-iac        | Parent IaC repository            |
| gitlab-agents  | Kubernetes agent configuration   |
