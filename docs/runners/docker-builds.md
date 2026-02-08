# Docker and DinD Builds

Guide for building and pushing container images using the GitLab runners.

## Overview

Two runners support Docker operations:

| Runner       | Use Case                      | Privileged |
| ------------ | ----------------------------- | ---------- |
| bates-docker | Running containers, no builds | No         |
| bates-dind   | Building images, docker push  | Yes        |

## Building Container Images

### Basic Docker Build

```yaml
build-image:
  stage: build
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    - docker build -t myapp:$CI_COMMIT_SHA .
```

### Push to GitLab Container Registry

```yaml
build-and-push:
  stage: build
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    # Tag as latest on main branch
    - |
      if [ "$CI_COMMIT_BRANCH" = "main" ]; then
        docker tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA $CI_REGISTRY_IMAGE:latest
        docker push $CI_REGISTRY_IMAGE:latest
      fi
```

### Multi-Stage Builds

```yaml
build-multistage:
  stage: build
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
    DOCKER_BUILDKIT: "1"
  script:
    - docker build --target production -t myapp:prod .
    - docker build --target development -t myapp:dev .
```

## Docker Compose

```yaml
integration-test:
  stage: test
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  before_script:
    - apk add --no-cache docker-compose
  script:
    - docker-compose -f docker-compose.test.yml up -d
    - docker-compose -f docker-compose.test.yml run --rm test
  after_script:
    - docker-compose -f docker-compose.test.yml down -v
```

## Build Caching

### Using GitLab's Cache

```yaml
build-with-cache:
  stage: build
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    # Pull previous image for cache
    - docker pull $CI_REGISTRY_IMAGE:latest || true
    # Build with cache
    - docker build --cache-from $CI_REGISTRY_IMAGE:latest -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

### Using BuildKit Cache

```yaml
build-with-buildkit:
  stage: build
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
    DOCKER_BUILDKIT: "1"
  script:
    - docker build \
      --build-arg BUILDKIT_INLINE_CACHE=1 \
      --cache-from $CI_REGISTRY_IMAGE:latest \
      -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
```

## Security Scanning

### Trivy Scanner

```yaml
scan-image:
  stage: test
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    - docker pull $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      aquasec/trivy:latest image --severity HIGH,CRITICAL \
      $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

## Best Practices

### 1. Always Use Specific Tags

```yaml
# Good
services:
  - docker:27-dind

# Avoid
services:
  - docker:dind  # May change unexpectedly
```

### 2. Wait for Docker Daemon

```yaml
before_script:
  - |
    for i in $(seq 1 30); do
      docker info && break
      echo "Waiting for Docker daemon..."
      sleep 1
    done
```

### 3. Clean Up After Builds

```yaml
after_script:
  - docker system prune -f
  - docker volume prune -f
```

### 4. Use .dockerignore

Create a `.dockerignore` file to speed up builds:

```
.git
node_modules
*.md
.gitlab-ci.yml
```

### 5. Multi-Platform Builds

```yaml
build-multiplatform:
  stage: build
  tags:
    - dind
    - privileged
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    - docker buildx create --use
    - docker buildx build \
      --platform linux/amd64,linux/arm64 \
      -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA \
      --push .
```

## Troubleshooting

### "Cannot connect to Docker daemon"

1. Ensure you're using the `dind` tag
2. Check that the service is defined
3. Verify DOCKER_HOST is set correctly

### "permission denied" errors

Ensure you're using privileged mode:

```yaml
tags:
  - dind
  - privileged
```

### Slow builds

1. Use build caching
2. Create a `.dockerignore` file
3. Order Dockerfile commands by change frequency
4. Use multi-stage builds to reduce image size
