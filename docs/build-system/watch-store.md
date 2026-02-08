---
title: Watch-Store Bootstrap
order: 10
---

# Watch-Store Bootstrap

`attic watch-store` is the mechanism that turns Nix builds into
incrementally cached operations. Rather than pushing the entire closure
to the binary cache after the build completes, watch-store pushes each
store path as it appears in `/nix/store`, making partial results
available to future builds immediately.

## How watch-store Works

When started as a background process, `attic watch-store <cache-name>`
opens an inotify (Linux) or FSEvents (macOS) watch on `/nix/store`. Each
time Nix finalizes a new store path -- meaning the derivation built
successfully and its output hash is registered -- watch-store detects the
new entry and pushes it to the named Attic cache.

The push is asynchronous relative to the build. Nix continues building
the next derivation in the dependency graph while the previous one
uploads. This overlap means that for most builds, the upload cost is
hidden behind computation time.

## Incremental Caching and Partial Failures

The key advantage of watch-store over end-of-build push is resilience to
partial failures. Consider a complex derivation tree with 80 intermediate
outputs:

- **End-of-build push**: If the build fails at output 60, zero outputs
  are cached. The next pipeline rebuilds all 60 from scratch.
- **watch-store**: Outputs 1 through 59 are already in the cache when the
  failure occurs. The next pipeline substitutes those 59 outputs
  instantly and resumes from output 60.

This property is especially valuable for long-running Rust compilations
(like the `attic` client itself) and for Nix builds that involve many
independent intermediate derivations (system libraries, toolchains,
compiler bootstraps).

## The Bootstrap Problem

watch-store depends on the `attic` CLI binary. The `attic` CLI is itself
a Nix derivation -- building it from source involves compiling a
substantial Rust codebase with Cargo, which can take 30-60 minutes on CI
runners.

This creates a circular dependency: to push derivations incrementally, we
need `attic`; to get `attic` quickly, we need it to already be cached; to
cache it, we need to have pushed it with `attic`.

## Bootstrap Sequence

The bootstrap logic resolves this circular dependency with a two-phase
approach:

### Phase 1: Attempt Substitution Only

```bash
nix build .#attic-client --out-link /tmp/attic-client --max-jobs 0
```

The `--max-jobs 0` flag tells Nix to fetch from configured substituters
(binary caches) but never build locally. If the `attic` client is already
in the cache, this completes in seconds. If not, it fails immediately --
there is no 60-minute wait.

### Phase 2a: Client Available (Common Case)

If phase 1 succeeded, the cached client binary is at
`/tmp/attic-client/bin/attic`. The CI job:

1. Authenticates with `attic login ci <server-url> <token>`.
2. Starts the background watcher with `attic watch-store <cache-name> &`.
3. Proceeds to the main `nix build` step. All new derivations stream to
   the cache in real time.
4. In `after_script`, stops watch-store and logs the push count.

### Phase 2b: Client Not Available (First Pipeline)

If phase 1 failed (the client is not in any cache), the CI job skips
watch-store entirely and falls back to end-of-build push:

1. Runs `nix build` as normal. This builds the `attic` client along with
   everything else.
2. After the build, pushes the complete closure with `attic push`.
3. Future pipelines now have the client in the cache and will follow the
   Phase 2a path.

The fallback means the very first pipeline for a fresh cache pays the
full cost. Every subsequent pipeline bootstraps watch-store in seconds.

## CI Lifecycle Integration

The watch-store lifecycle maps to GitLab CI's job phases:

| CI Phase | Action |
|---|---|
| `before_script` | Discover Attic server endpoint. Attempt client substitution. If available, authenticate and start watch-store in the background. |
| `script` | Run `nix build` normally. Derivations are pushed incrementally by the background watch-store process. |
| `after_script` | Terminate watch-store. Log the number of store paths pushed. Run a final `attic push result-*` as a belt-and-suspenders measure to ensure the top-level outputs and their closures are fully cached. |

The final explicit push in `after_script` is not strictly necessary when
watch-store is running, but it guards against edge cases where
watch-store might miss a path (for example, if the process is terminated
before it processes the last batch of events).

## Monitoring

watch-store logs its activity to stderr. In CI job logs, look for:

```
watch-store pushed 47 store paths incrementally
```

A high number indicates many cache misses were filled during the build.
A low number (or zero) means most derivations were already cached. Both
are normal -- the first indicates a productive cache-warming run, and the
second indicates a mature cache.

## Related Documents

- [Greedy Build Pattern](greedy-build-pattern.md) -- the pipeline
  strategy that drives watch-store usage
- [Container Builds](containers.md) -- how built derivations become
  container images
