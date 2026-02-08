---
title: Nix Builds
order: 30
---

# Nix Builds

The `nix` runner provides a NixOS-based environment with Nix flakes enabled
and the Attic binary cache pre-configured.

## Environment

The following environment variables are set automatically on every nix runner
pod:

- `ATTIC_SERVER` -- URL of the Attic cache server (in the
  `attic-cache-dev` namespace).
- `ATTIC_CACHE` -- name of the binary cache to push to and pull from.

These variables allow CI jobs to interact with the Attic cache without
manual configuration.

## Recommended Pipeline Pattern

A typical Nix CI job follows this sequence:

1. **Build** the derivation with `nix build`.
2. **Push** the result to the Attic cache with `attic push`.

```yaml
nix-build:
  tags:
    - nix
    - flakes
  script:
    - nix build .#package
    - attic push "$ATTIC_CACHE" ./result
```

## watch-store for Incremental Caching

For long-running builds, use `attic watch-store` to incrementally populate
the cache as store paths are realized. This is useful when a build produces
many intermediate derivations:

```yaml
nix-build-large:
  tags:
    - nix
    - flakes
  script:
    - attic watch-store "$ATTIC_CACHE" &
    - nix build .#large-package
    - wait
```

The background `watch-store` process monitors the Nix store and pushes new
paths to Attic as they appear, rather than waiting for the entire build to
complete.

## Bootstrap Behavior

The first build on a fresh cache has no cached paths to pull from, so it
will be slow. Subsequent builds benefit from the cache and complete
significantly faster. This is expected and does not indicate a
misconfiguration.

## Attic Binary

The Attic binary is located at `/bin/atticd` inside the container. Note that
the binary is called `atticd`, not `attic-server`.

## Resource Limits

Nix builds tend to be CPU-intensive due to derivation evaluation and
compilation:

- **CPU**: 2 cores
- **Memory**: 4Gi

If builds fail with out-of-memory errors or take excessively long, consider
adjusting the resource limits. See [HPA Tuning](hpa-tuning.md).
