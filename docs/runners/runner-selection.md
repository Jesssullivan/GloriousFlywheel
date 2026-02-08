# Runner Selection Guide

Choose the right runner for your CI/CD job based on your requirements.

## Decision Tree

```
What does your job need?
│
├─► Build container images? ──────► dind (tags: dind, privileged)
│
├─► Test on RHEL 8? ──────────────► rocky8 (tags: rocky8, rhel8)
│
├─► Test on RHEL 9? ──────────────► rocky9 (tags: rocky9, rhel9)
│
├─► Nix/Flakes build? ────────────► nix (tags: nix, flakes)
│
└─► General purpose? ─────────────► docker (tags: docker, linux)
```

## Runner Comparison

| Feature         | docker | dind | rocky8 | rocky9 | nix    |
| --------------- | ------ | ---- | ------ | ------ | ------ |
| Privileged mode | No     | Yes  | No     | No     | No     |
| Docker builds   | No     | Yes  | No     | No     | No     |
| DNF packages    | No     | No   | Yes    | Yes    | No     |
| APK packages    | Yes    | Yes  | No     | No     | No     |
| Nix packages    | No     | No   | No     | No     | Yes    |
| glibc version   | 2.34   | 2.36 | 2.28   | 2.34   | N/A    |
| Python default  | 3.11   | 3.11 | 3.6    | 3.9    | varies |
| Concurrent jobs | 8      | 4    | 4      | 4      | 4      |

## Detailed Use Cases

### docker

**Best for:**

- Shell scripts and automation
- Node.js/Python/Go builds (with apk install)
- Unit tests (non-containerized)
- Linting and static analysis
- Artifact packaging

**Example:**

```yaml
lint-check:
  tags:
    - docker
    - linux
  script:
    - apk add --no-cache shellcheck
    - shellcheck scripts/*.sh
```

### dind

**Best for:**

- Building Docker images
- Pushing to container registries
- Docker Compose integration tests
- Kaniko builds (alternative)
- Multi-stage builds

**Example:**

```yaml
build-and-push:
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
```

### rocky8

**Best for:**

- RHEL 8 production deployment testing
- Ansible playbook testing against RHEL 8
- Legacy Python 3.6 compatibility
- RPM package building
- Applications requiring glibc 2.28

**Example:**

```yaml
test-ansible-rhel8:
  tags:
    - rocky8
    - rhel8
  script:
    - dnf install -y python3 python3-pip
    - pip3 install ansible ansible-lint
    - ansible-lint playbook.yml
    - ansible-playbook --check playbook.yml
```

### rocky9

**Best for:**

- RHEL 9 production deployment testing
- Modern RHEL development
- cgroups v2 testing
- Systemd-based applications
- Applications requiring glibc 2.34

**Example:**

```yaml
test-systemd-service:
  tags:
    - rocky9
    - rhel9
  script:
    - dnf install -y systemd
    - cp myservice.service /etc/systemd/system/
    - systemd-analyze verify myservice.service
```

### nix

**Best for:**

- Reproducible builds
- Flakes-based projects
- Cross-compilation
- Hermetic builds
- Nix derivation testing

**Example:**

```yaml
nix-build:
  tags:
    - nix
    - flakes
  script:
    - nix build .#default
    - nix flake check
    # Push to Attic cache
    - attic push main result
```

## Tag Combinations

You can combine tags for more specific runner selection:

```yaml
# Any docker-capable runner (docker or dind)
job1:
  tags:
    - docker

# Only the standard docker runner (not dind)
job2:
  tags:
    - docker
    - linux
    - amd64

# Only DinD runner
job3:
  tags:
    - dind
    - privileged

# Any Rocky Linux runner
job4:
  tags:
    - linux
  # Will match rocky8 or rocky9

# Specifically Rocky 8
job5:
  tags:
    - rocky8
    - rhel8
```

## Performance Tips

1. **Use the smallest runner** that meets your needs
2. **Avoid dind** if you don't need Docker builds (it has higher resource overhead)
3. **Cache dependencies** where possible (npm, pip, etc.)
4. **Use Nix** for truly reproducible builds with automatic caching
5. **Parallelize** independent jobs across different runners

## Common Mistakes

### Wrong: Using dind for non-container jobs

```yaml
# Don't do this - wastes resources
lint:
  tags:
    - dind
  script:
    - pylint src/
```

### Right: Use docker for simple jobs

```yaml
# Much more efficient
lint:
  tags:
    - docker
  script:
    - apk add py3-pylint
    - pylint src/
```

### Wrong: Hardcoding Rocky version unnecessarily

```yaml
# Don't do this unless you specifically need Rocky 8
build:
  tags:
    - rocky8
  script:
    - echo "Hello World"
```

### Right: Use generic tags when possible

```yaml
# This allows scheduler flexibility
build:
  tags:
    - docker
  script:
    - echo "Hello World"
```
