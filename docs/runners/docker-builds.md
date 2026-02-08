---
title: Docker Builds
order: 20
---

# Docker Builds

The `dind` runner provides Docker-in-Docker capability for CI jobs that need
to build, tag, or push container images.

## How It Works

The `dind` runner launches a `docker:dind` sidecar service alongside the job
container. The Docker daemon runs inside the sidecar, and the job container
communicates with it over the loopback interface.

- The sidecar runs with `--tls=false` because TLS is unnecessary on an
  internal loopback connection within the same pod.
- There is no need to set `DOCKER_TLS_CERTDIR` on the service container.
- Set `DOCKER_HOST=tcp://localhost:2375` in your CI job to connect to the
  daemon.

## Example Job

```yaml
build-image:
  tags:
    - dind
    - privileged
  variables:
    DOCKER_HOST: tcp://localhost:2375
  script:
    - docker build -t my-image:latest .
    - docker push my-image:latest
```

## Resource Limits

Container builds are resource-intensive. The `dind` runner is configured with
higher limits than the other runner types:

- **CPU**: 4 cores
- **Memory**: 8Gi

These limits apply to the job pod as a whole. If builds fail with
out-of-memory errors, see [HPA Tuning](hpa-tuning.md) for how to adjust
limits.

## Kaniko Alternative

For rootless container builds that do not require a privileged runner, use
[Kaniko](https://github.com/GoogleContainerTools/kaniko) on the standard
`docker` runner. Kaniko builds images in userspace and does not need a Docker
daemon. This avoids the security implications of running privileged
containers. See [Security Model](security-model.md) for details on the
privilege boundary.

## Privileged Mode

The `dind` runner is the only runner type that runs in privileged mode. This
is required because the Docker daemon inside the sidecar needs access to
kernel features (cgroups, namespaces) that are unavailable to unprivileged
containers.
