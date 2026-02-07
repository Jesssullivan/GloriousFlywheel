# Greedy Build → Immediately Push Pattern

## Overview

This pattern ensures build artifacts are cached even when downstream stages fail, enabling resumable builds and maximizing cache hit rates across CI/CD pipelines.

## The Problem

Traditional CI/CD pipelines wait for validation stages before building:

```
validate → build → test → deploy
```

If validation fails, no build artifacts are cached. If the build succeeds but tests fail, subsequent pipeline runs must rebuild from scratch.

## The Solution: Greedy Building

Greedy builds start immediately and push to cache regardless of downstream outcomes:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   build     │     │  validate   │     │   deploy    │
│ needs: []   │     │             │     │             │
│ (parallel)  │     │ (parallel)  │     │ (sequential)│
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       ▼                   ▼                   │
   ┌────────┐         ┌────────┐              │
   │ cache  │         │ check  │              │
   │ push   │         │        │──────────────┘
   └────────┘         └────────┘
       │
       ▼
   Cache populated
   (even if deploy fails)
```

## Key Principles

### 1. Build Jobs Use `needs: []`

Jobs without dependencies start immediately when the pipeline begins:

```yaml
nix:build:
  stage: build
  needs: [] # No dependencies - starts immediately
  script:
    - nix build .#package --out-link result
```

### 2. Cache Push is Non-Blocking

Cache failures are logged but don't fail the job:

```yaml
script:
  - nix build .#package --out-link result
  # Push to cache (non-blocking)
  - |
    nix run .#attic -- push main result || echo "Cache push failed (non-blocking)"
```

This ensures:

- Build artifacts are always produced
- Cache issues don't block development
- Failures are visible in logs for debugging

### 3. Artifacts Preserved on Failure

GitLab preserves artifacts even when downstream stages fail:

```yaml
artifacts:
  paths:
    - result*
  expire_in: 1 day
  when: always # Optional: keep even if this job fails
```

### 4. Subsequent Pipelines Use Cache

Future builds automatically pull cached derivations:

```yaml
nix:build:
  script:
    # This will use cached derivations if available
    - nix build .#package --print-build-logs
```

## Implementation in This Repository

### CI/CD Pipeline Structure

```yaml
stages:
  - build # Greedy: nix:build runs with needs: []
  - test # Validation: tofu validate, plan
  - deploy # Sequential: requires test success
  - verify # Health checks
```

### Build Job

```yaml
nix:build:
  stage: build
  needs: [] # Greedy - starts immediately
  script:
    - nix build .#attic --print-build-logs --out-link result
    - |
      if [ -n "${ATTIC_SERVER:-}" ]; then
        nix run .#attic -- login ci "$ATTIC_SERVER" || echo "Login failed"
        nix run .#attic -- push main result || echo "Push failed"
      fi
  artifacts:
    paths:
      - result*
    expire_in: 1 day
```

## Benefits

| Benefit                | Description                                |
| ---------------------- | ------------------------------------------ |
| **Faster iteration**   | Failed validation doesn't waste build time |
| **Resumable builds**   | Pick up where you left off after failures  |
| **Higher cache hits**  | More derivations cached = more hits        |
| **Reduced CI costs**   | Less redundant building                    |
| **Better parallelism** | Build and validate simultaneously          |

## Tradeoffs

| Consideration                    | Mitigation                                          |
| -------------------------------- | --------------------------------------------------- |
| Cache contains unvalidated code  | Cache is internal-only; validation gates deployment |
| More initial pipeline complexity | Simplified with clear job structure                 |
| Potential for cache bloat        | GC worker prunes old derivations                    |

## Incremental Push with watch-store

The greedy pattern ensures builds **start** immediately. The incremental
push layer ensures derivations are cached **as they're built**, not just
at the end.

### The Problem with End-of-Build Push

```
Pipeline A: nix build .#attic-client  (60 min build)
  min 0-45: building rustc, cargo deps, nix libs...
  min 45:   build FAILS (OOM, timeout, flaky test)
  result:   zero derivations cached — 45 minutes wasted

Pipeline B: nix build .#attic-client
  starts from scratch again
```

### The Solution: watch-store

`attic watch-store` monitors the local Nix store and pushes new paths to
the cache as they appear. It runs as a background process during the build.

```
Pipeline A: nix build .#attic-client  (60 min build)
  min 0:    watch-store starts in background
  min 1:    rustc derivation built → pushed to cache
  min 5:    cargo deps built → pushed to cache
  min 30:   nix libs built → pushed to cache
  min 45:   build FAILS
  result:   30+ derivations already cached

Pipeline B: nix build .#attic-client
  min 0:    rustc → cache hit (instant)
  min 0:    cargo deps → cache hit (instant)
  min 0:    nix libs → cache hit (instant)
  min 1:    only the remaining derivations need building
```

### Bootstrap Sequence

watch-store needs the `attic` binary, which is one of the things we're
building. The bootstrap logic handles this chicken-and-egg:

```yaml
# Try to get attic from cache (substituters only, no local builds)
nix build .#attic-client --out-link /tmp/attic-client --max-jobs 0

# If cached (subsequent pipelines): start watch-store
/tmp/attic-client/bin/attic watch-store main &

# If not cached (first pipeline): skip watch-store
# The end-of-build push populates the cache for next time
```

`--max-jobs 0` tells Nix to only use substituters, never build locally.
If the attic client isn't in any cache, this fails instantly (no 60-minute
wait). The first pipeline falls back to end-of-build push, which seeds
the cache. Every subsequent pipeline has watch-store active.

### Implementation

The watch-store lifecycle is managed in `.nix-build-base`:

- **before_script**: discover Attic server, bootstrap client, start watch-store
- **script**: `nix build` proceeds normally; derivations stream to cache
- **after_script**: stop watch-store, log push count

Each job also does a final `attic push result-*` as belt-and-suspenders to
ensure the complete closure is cached.

## Monitoring Cache Effectiveness

Check cache hit rates in build logs:

```bash
# High cache hit rate (good)
copying path '/nix/store/...' from 'https://attic-cache.beehive.bates.edu'...

# Cache miss (building locally)
building '/nix/store/...drv'...
```

Check watch-store activity in the job's after_script output:

```
watch-store pushed 47 store paths incrementally
```

## Related Resources

- [Nix Binary Cache Documentation](https://nixos.org/manual/nix/stable/package-management/binary-cache-substituter.html)
- [Attic Documentation](https://github.com/zhaofengli/attic)
- [Attic watch-store](https://github.com/zhaofengli/attic#watch-store)
- [GitLab CI/CD needs Keyword](https://docs.gitlab.com/ee/ci/yaml/#needs)
