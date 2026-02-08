# Campus Build Infrastructure Research

## Shared Build & Cache Infrastructure

**Date:** 2026-02-05
**Status:** Initial Research Phase

---

## Executive Summary

This document consolidates research on build infrastructure options for a ~50 developer campus environment. The research evaluates Bazel remote execution, Nix binary caching, and integration patterns to inform infrastructure decisions.

### Key Findings

1. **Start with bazel-remote + existing MinIO** - The simplest path to Bazel caching leverages your existing MinIO storage with minimal new infrastructure (2 CPU, 4Gi RAM).

2. **Full nixpkgs mirror is impractical** - At 705TB and growing ~8.4TB/month, mirroring is infeasible. Instead, use a hybrid architecture: Attic (current) + NCPS caching proxy.

3. **Keep Nix and Bazel caches separate** - The systems use fundamentally different caching models (input-addressed vs content-addressed). Integration via rules_nixpkgs works, but shared storage doesn't.

4. **Phased deployment is critical** - Universities that succeed with build infrastructure take 12-18 months, starting with 2-3 pilot projects.

5. **ROI is strong** - Typical 50-85x return on infrastructure investment through developer time savings.

---

## 1. Bazel Remote Execution & Caching

### Recommended Starting Point: bazel-remote

[bazel-remote](https://github.com/buchgr/bazel-remote) is a production-proven cache server that integrates directly with your existing MinIO.

**Why bazel-remote:**

- Battle-tested since 2018, handling TBs/day in production
- Direct S3/MinIO integration
- Simple deployment (single container)
- Supports both gRPC and HTTP protocols
- LRU eviction with configurable limits

**Resource Requirements:**

| Component     | Replicas | CPU   | Memory | Storage             |
| ------------- | -------- | ----- | ------ | ------------------- |
| bazel-remote  | 2        | 1 CPU | 2Gi    | Backed by MinIO     |
| **Total New** | -        | 2 CPU | 4Gi    | Uses existing 800Gi |

**Configuration:**

```yaml
# bazel-remote config.yaml
dir: /data
max_size: 100 # GiB
s3:
  endpoint: minio.attic-cache.svc.cluster.local:9000
  bucket: bazel-cache
  auth_method: access_key
  access_key_id: ${S3_ACCESS_KEY_ID}
  secret_access_key: ${S3_SECRET_ACCESS_KEY}
  disable_ssl: true # Internal MinIO
```

**Client Configuration (.bazelrc):**

```bash
build --remote_cache=grpc://bazel-cache.prod-cluster.example.com:9092
build --remote_upload_local_results=true
build --remote_download_minimal
```

### Full Remote Execution Options

If remote execution (not just caching) becomes necessary:

| Solution                  | Best For                        | Complexity | Resources    |
| ------------------------- | ------------------------------- | ---------- | ------------ |
| **BuildBuddy Enterprise** | Best balance of features/ease   | Medium     | 12 CPU, 46Gi |
| **Buildbarn**             | Nix integration via Tweag       | High       | 18 CPU, 42Gi |
| **Buildfarm**             | Google reference implementation | Medium     | 10 CPU, 20Gi |
| **NativeLink**            | High-performance Rust impl      | Medium     | Varies       |

**Recommendation:** Defer remote execution unless build times remain problematic after caching. Cache-only provides 80% of benefits with 20% of complexity.

---

## 2. Nix Binary Cache Infrastructure

### Current State

Attic is deployed on dev-cluster (dev) and planned for prod-cluster (prod) with:

- MinIO S3 storage (10Gi dev, 800Gi prod)
- Chunk-level deduplication (4-6x effective compression)
- Auth-free access on internal network

### Why Full Mirror is Impractical

| Metric               | Value         |
| -------------------- | ------------- |
| cache.nixos.org size | ~705 TB       |
| Growth rate          | ~8.4 TB/month |
| Monthly S3 cost      | ~$5,500       |
| Store paths          | ~667 million  |

**Conclusion:** Focus on caching what's actually used, not mirroring everything.

### Recommended Hybrid Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Developer Workstations                   │
│  substituters = [                                           │
│    "https://attic-cache.prod-cluster.example.com/main"              │
│    "https://ncps.prod-cluster.example.com"                          │
│    "https://cache.nixos.org"                               │
│  ]                                                          │
└─────────────────────────────────────────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│     Attic        │  │      NCPS        │  │  cache.nixos.org │
│  (Campus builds) │  │  (Proxy layer)   │  │    (Upstream)    │
│  MinIO backend   │  │  Local SSD       │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

**Components:**

1. **Attic (current)** - Stores campus-built packages with deduplication
2. **NCPS (add later)** - Caching proxy for upstream, reduces bandwidth
3. **Campus overlay** - Flake with organization-specific packages

### Storage Estimates

| Component             | Initial   | 6 Months  | 1 Year    |
| --------------------- | --------- | --------- | --------- |
| Attic (campus builds) | 50Gi      | 150Gi     | 300Gi     |
| NCPS (upstream cache) | 100Gi     | 300Gi     | 500Gi     |
| **Total**             | **150Gi** | **450Gi** | **800Gi** |

Your existing 800Gi MinIO allocation is well-sized for 1+ years.

---

## 3. Bazel + Nix Integration

### Can They Share Cache?

**No, not directly.** The caching models are fundamentally different:

| Aspect      | Nix Store       | Bazel Cache       |
| ----------- | --------------- | ----------------- |
| Granularity | Package-level   | Action-level      |
| Addressing  | Input-addressed | Content-addressed |
| Location    | `/nix/store`    | `bazel-out/`      |

### Recommended Pattern: Separate Caches, Shared Backend

```
┌─────────────────────────────────────────────────────────────┐
│                      MinIO (Shared S3)                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │  attic bucket   │    │ bazel-cache     │                 │
│  │  (Nix NARs)     │    │  bucket         │                 │
│  └─────────────────┘    └─────────────────┘                 │
│           │                      │                          │
│           ▼                      ▼                          │
│     ┌───────────┐         ┌───────────────┐                │
│     │   Attic   │         │  bazel-remote │                │
│     │  Server   │         │    Server     │                │
│     └───────────┘         └───────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### Using rules_nixpkgs

[rules_nixpkgs](https://github.com/tweag/rules_nixpkgs) allows Bazel to use Nix-provided toolchains:

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

**Supported Toolchains:** C/C++, Go, Java, Python, Rust, Haskell, Node.js

**Limitation:** Remote execution with rules_nixpkgs is experimental. Workers need access to `/nix/store` paths via NFS or similar.

---

## 4. Phased Implementation Plan

### Phase 1: Foundation (Current - 3 Months)

**Goals:**

- Validate Attic on dev-cluster
- Onboard 2-3 pilot projects
- Establish baseline metrics

**Deliverables:**

- [ ] Attic deployed and accessible
- [ ] Example flake.nix with cache configuration
- [ ] GitLab CI template for Nix builds
- [ ] Basic monitoring (uptime, storage)
- [ ] Documentation for pilot users

**Success Criteria:**

- Cache hit rate >60% after 2 weeks
- No unplanned downtime >30 minutes
- Positive pilot feedback

### Phase 2: Expansion (3-6 Months)

**Goals:**

- Deploy to prod-cluster (production)
- Add self-hosted GitLab runners
- Evaluate Bazel caching need

**Deliverables:**

- [ ] Production Attic on prod-cluster with HA PostgreSQL
- [ ] Self-hosted GitLab runners with Nix support
- [ ] bazel-remote deployment (if needed)
- [ ] Comprehensive monitoring and alerting
- [ ] User training materials

**Success Criteria:**

- 10+ projects using cache
- Cache hit rate >70%
- <5 support tickets/week

### Phase 3: Full Campus (6-12 Months)

**Goals:**

- Campus-wide availability
- Student access for coursework
- Long-term sustainability

**Deliverables:**

- [ ] Self-service onboarding
- [ ] SSO integration
- [ ] NCPS caching proxy (if needed)
- [ ] Documentation site
- [ ] Annual review process

**Success Criteria:**

- 30+ projects using cache
- <2 hours/week operations overhead
- Documented succession plan

---

## 5. Cost-Benefit Analysis

### Infrastructure Costs

| Component               | Monthly Est.  |
| ----------------------- | ------------- |
| Attic (API + GC pods)   | $18-33        |
| PostgreSQL cluster      | $25-40        |
| MinIO (existing)        | $0            |
| bazel-remote (if added) | $10-15        |
| **Total**               | **$53-88/mo** |

### Developer Time Savings

| Metric              | Value             |
| ------------------- | ----------------- |
| Developers          | 50                |
| Builds/day          | ~100 (2 per dev)  |
| Avg build time      | 10 min            |
| Cache improvement   | 50% (5 min saved) |
| **Daily savings**   | 8.3 hours         |
| **Monthly savings** | ~170 hours        |

**ROI at $75/hr loaded cost:**

- Monthly savings: $12,750
- Monthly cost: $70 (avg)
- **ROI: 182x**

---

## 6. Decision Framework

### When to Add Bazel Caching

Add bazel-remote when:

- [ ] Multiple projects use Bazel for builds
- [ ] CI pipeline includes Bazel test stages
- [ ] Build times exceed 5 minutes
- [ ] Developers request faster builds

### When to Add NCPS Proxy

Add NCPS when:

- [ ] Bandwidth to cache.nixos.org becomes bottleneck
- [ ] Same upstream packages rebuilt frequently
- [ ] Network costs are a concern
- [ ] Offline build capability needed

### When to Consider Remote Execution

Consider full RBE when:

- [ ] Cache-only provides <50% improvement
- [ ] Build parallelism limited by local resources
- [ ] CI queues exceed 10 minutes
- [ ] Multiple architectures (aarch64) needed

---

## 7. References

### Bazel Resources

- [bazel-remote](https://github.com/buchgr/bazel-remote) - Simple cache server
- [BuildBuddy](https://github.com/buildbuddy-io/buildbuddy) - Full platform
- [Buildbarn](https://github.com/buildbarn/bb-deployments) - Nix integration
- [Bazel Remote Caching](https://bazel.build/remote/caching)

### Nix Resources

- [Attic](https://github.com/zhaofengli/attic) - Binary cache server
- [NCPS](https://github.com/kalbasit/ncps) - Caching proxy
- [rules_nixpkgs](https://github.com/tweag/rules_nixpkgs) - Bazel integration
- [Nix + Bazel Guide](https://nix-bazel.build/)

### Case Studies

- [Tweag: Bazel + Nix Migration](https://www.tweag.io/blog/2022-12-15-bazel-nix-migration-experience/)
- [LinkedIn Gradle Caching](https://engineering.linkedin.com/blog/2019/productivity-at-scale--how-we-improved-build-time-with-gradle-bu) - 800+ dev-hours/day saved
- [Mercury: Buck2 + Nix](https://serokell.io/blog/haskell-in-production-mercury) - 1.2M line Haskell

### University Examples

- [MIT ORCD](https://orcd.mit.edu/) - 80,000+ CPU cores
- [Stanford Research Computing](https://srcc.stanford.edu/) - FarmShare model
- [GRICAD HPC](https://dl.acm.org/doi/10.1145/3152493.3152556) - Nix in HPC

---

## Appendix A: Quick Start Commands

### Use Attic Cache

```nix
# In flake.nix
{
  nixConfig = {
    extra-substituters = [ "https://attic-cache.prod-cluster.example.com" ];
    extra-trusted-substituters = [ "https://attic-cache.prod-cluster.example.com" ];
  };
}
```

### Push to Cache (CI)

```yaml
nix:build:
  script:
    - nix build .#package --out-link result
    - nix run .#attic -- push main result || echo "Cache push (non-blocking)"
```

### Configure Bazel (if added)

```bash
# .bazelrc
build --remote_cache=grpc://bazel-cache.prod-cluster.example.com:9092
build --remote_upload_local_results=true
build --remote_download_minimal

# CI configuration
build:ci --remote_cache=grpc://bazel-cache.bazel-cache.svc.cluster.local:9092
```

---

## Appendix B: Architecture Diagrams

### Current State (Phase 1)

```
┌─────────────────────────────────────────────────────────────┐
│                      Dev Cluster                         │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │    Attic     │───▶│  PostgreSQL  │    │    MinIO     │  │
│  │    Server    │    │    (CNPG)    │    │  (10Gi dev)  │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                                        ▲          │
│         └────────────────────────────────────────┘          │
│                      NAR storage                            │
└─────────────────────────────────────────────────────────────┘
```

### Target State (Phase 3)

```
┌─────────────────────────────────────────────────────────────┐
│                       Prod Cluster                          │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │    Attic     │───▶│  PostgreSQL  │    │    MinIO     │  │
│  │   (HA x2)    │    │  (HA x3)     │    │  (800Gi)     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                                        ▲          │
│         │            ┌──────────────┐            │          │
│         │            │ bazel-remote │────────────┤          │
│         │            │   (x2)       │            │          │
│         │            └──────────────┘            │          │
│         │                                        │          │
│         │            ┌──────────────┐            │          │
│         │            │    NCPS      │────────────┘          │
│         │            │   (proxy)    │                       │
│         │            └──────────────┘                       │
│         │                   │                               │
│         └───────────────────┼───────────────────────────────┤
│                      NAR storage                            │
│                             │                               │
│                             ▼                               │
│                    cache.nixos.org                          │
└─────────────────────────────────────────────────────────────┘
```
