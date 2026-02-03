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

## Monitoring Cache Effectiveness

Check cache hit rates in build logs:

```bash
# High cache hit rate (good)
copying path '/nix/store/...' from 'https://attic-cache.rigel.bates.edu'...

# Cache miss (building locally)
building '/nix/store/...drv'...
```

## Related Resources

- [Nix Binary Cache Documentation](https://nixos.org/manual/nix/stable/package-management/binary-cache-substituter.html)
- [Attic Documentation](https://github.com/zhaofengli/attic)
- [GitLab CI/CD needs Keyword](https://docs.gitlab.com/ee/ci/yaml/#needs)
