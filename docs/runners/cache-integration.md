# Cache Integration

How to use the Bazel remote cache and Attic Nix binary cache from CI jobs.

## Bazel Remote Cache

### Endpoint

The Bazel remote cache runs as an in-cluster gRPC service:

```
grpc://bazel-cache.attic-cache-dev.svc.cluster.local:9092
```

The `BAZEL_REMOTE_CACHE` environment variable is injected into `docker` and
`nix` runner pods automatically.

### .bazelrc Configuration

Add a `runner-pool` config section to your project's `.bazelrc`:

```
# .bazelrc
build:runner-pool --remote_cache=grpc://bazel-cache.attic-cache-dev.svc.cluster.local:9092
build:runner-pool --remote_upload_local_results=true
build:runner-pool --remote_timeout=60
```

Or reference the environment variable directly:

```
build:runner-pool --remote_cache=${BAZEL_REMOTE_CACHE}
build:runner-pool --remote_upload_local_results=true
build:runner-pool --remote_timeout=60
```

### CI Usage

```yaml
include:
  - component: $CI_SERVER_FQDN/{org}/projects/iac/attic-cache/docker-job@main
    inputs:
      stage: build
      script: bazel build --config=runner-pool //...
```

The `--config=runner-pool` flag activates the remote cache settings. Local
builds (without the flag) are unaffected.

### Cache Behavior

- **Read + write**: Jobs both read from and write to the cache by default.
- **Read-only**: Set `--remote_upload_local_results=false` if you only want
  cache hits without populating the cache.
- **Scope**: The cache is shared across all projects in the organization. Cache keys are
  content-addressed, so identical inputs produce identical cache entries
  regardless of which project wrote them.

## Attic Nix Binary Cache

### Endpoint

The Attic binary cache is available at:

```
https://attic.dev-cluster.example.com
```

Nix runners are pre-configured with this cache as a substituter. Builds
automatically:

1. Check the Attic cache for existing store paths.
2. Build anything not cached.
3. Push newly-built paths back to the cache.

### Downstream Project Setup

To use the Attic cache from a downstream project's Nix runner job:

```yaml
include:
  - component: $CI_SERVER_FQDN/{org}/projects/iac/attic-cache/nix-job@main
    inputs:
      stage: build
      script: nix build .#default
```

The `nix-job` component handles Attic authentication and cache configuration.
No additional setup is required in the downstream project.

### Local Development

To pull from the Attic cache locally (read-only, no auth required):

```bash
# Add the cache as a substituter in your nix.conf or flake.nix
extra-substituters = https://attic.dev-cluster.example.com
extra-trusted-public-keys = attic-cache:YOUR_PUBLIC_KEY_HERE
```

Or in `flake.nix`:

```nix
{
  nixConfig = {
    extra-substituters = [ "https://attic.dev-cluster.example.com" ];
    extra-trusted-public-keys = [ "attic-cache:YOUR_PUBLIC_KEY_HERE" ];
  };
}
```

### Cache Warm Script

The `scripts/cache-warm.sh` script pre-populates the Attic cache with
commonly-used derivations:

```bash
# Run from the attic-cache repo root
./scripts/cache-warm.sh
```

This is run periodically by CI to ensure cache hit rates stay high. It builds
and pushes the most frequently-used dependencies across projects in the organization.

## Troubleshooting

### Bazel cache misses

- Verify `BAZEL_REMOTE_CACHE` is set: `echo $BAZEL_REMOTE_CACHE` in your job script.
- Confirm you are using `--config=runner-pool`.
- Check that the cache endpoint is reachable: `grpcurl bazel-cache.attic-cache-dev.svc.cluster.local:9092 list`.
- Different compiler versions, toolchains, or `--host_platform` flags produce
  different cache keys. Align toolchains across projects for maximum hit rate.

### Attic cache misses

- Ensure the job uses the `nix-job` component (not a plain `docker` runner).
- Check that `attic.dev-cluster.example.com` is resolvable from the pod:
  `nslookup attic.dev-cluster.example.com`.
- Verify the Attic token is mounted (the `nix-job` component handles this
  automatically).
- Flake inputs (e.g., `nixpkgs`) that differ between projects produce
  different store paths. Pin inputs to the same revision for shared caching.
