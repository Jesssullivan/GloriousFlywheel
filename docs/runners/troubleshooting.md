# Runner Troubleshooting Guide

Common issues and their solutions for GitLab Runners.

## Quick Diagnostics

```bash
# Check if runners are running
kubectl get pods -n bates-ils-runners

# Check HPA status
kubectl get hpa -n bates-ils-runners

# View recent events
kubectl get events -n bates-ils-runners --sort-by='.lastTimestamp' | tail -20

# Check runner logs
kubectl logs -n bates-ils-runners -l release=bates-docker --tail=50
```

## Common Issues

### Job Stuck in "Pending"

**Symptoms:**

- Job shows "Pending" status in GitLab
- "This job is stuck because you don't have any active runners"

**Causes & Solutions:**

1. **No matching tags**

   ```yaml
   # Wrong - no runner has these exact tags
   job:
     tags:
       - custom-tag
       - another-tag
   ```

   Fix: Use correct tags from [README.md](README.md#available-runners)

2. **Runner pods not running**

   ```bash
   kubectl get pods -n bates-ils-runners
   # If 0/1 Ready, check logs:
   kubectl logs -n bates-ils-runners deployment/bates-docker
   ```

3. **Runner not registered**
   ```bash
   # Check runner status in GitLab
   # Group > Settings > CI/CD > Runners
   ```

### Job Fails Immediately

**Symptoms:**

- Job starts but fails within seconds
- Error: "Job failed: prepare environment"

**Causes & Solutions:**

1. **Image pull failure**

   ```yaml
   # Check if image exists and is accessible
   job:
     image: my-private-registry/image:tag
   ```

   Fix: Use public images or configure registry credentials

2. **Resource limits exceeded**

   ```bash
   kubectl describe pod <job-pod-name> -n bates-ils-runners
   # Look for "OOMKilled" or resource errors
   ```

3. **Privileged mode required but not enabled**

   ```yaml
   # Wrong - trying to run docker without dind
   job:
     tags:
       - docker
     script:
       - docker build . # This will fail!
   ```

   Fix: Use `dind` tag for Docker builds

### DinD Build Failures

**Symptoms:**

- "Cannot connect to the Docker daemon"
- "docker: command not found"

**Solutions:**

1. **Missing service configuration**

   ```yaml
   # Correct DinD setup
   build:
     tags:
       - dind
       - privileged
     services:
       - docker:27-dind
     variables:
       DOCKER_HOST: tcp://localhost:2375
       DOCKER_TLS_CERTDIR: ""
     script:
       - docker build .
   ```

2. **Docker daemon not ready**
   ```yaml
   build:
     before_script:
       # Wait for Docker daemon
       - |
         for i in $(seq 1 30); do
           docker info && break
           echo "Waiting for Docker..."
           sleep 1
         done
     script:
       - docker build .
   ```

### Nix Build Failures

**Symptoms:**

- "error: experimental Nix feature 'flakes' is disabled"
- Slow builds (no cache hits)

**Solutions:**

1. **Flakes not enabled**

   The Nix runner has flakes enabled by default. If you see this error, ensure you're using the `nix` tag:

   ```yaml
   job:
     tags:
       - nix
       - flakes
   ```

2. **Cache misses**

   Check Attic configuration:

   ```yaml
   job:
     tags:
       - nix
     script:
       - echo "Attic server: $ATTIC_SERVER"
       - nix build .#default
       # Push to cache after successful build
       - attic push main result
   ```

3. **Nix store full**

   The Nix store is an emptyDir with 20Gi limit. For large builds:

   ```yaml
   job:
     variables:
       NIX_BUILD_CORES: "2" # Limit parallelism
     script:
       - nix-collect-garbage -d # Clean before build
       - nix build .#default
   ```

### Rocky Linux Package Issues

**Symptoms:**

- "No match for argument: <package>"
- DNF errors

**Solutions:**

1. **Package name differences**

   Rocky 8 and 9 have different package names:

   ```yaml
   # Rocky 8
   job-rocky8:
     tags: [rocky8]
     script:
       - dnf install -y python3 # Python 3.6

   # Rocky 9
   job-rocky9:
     tags: [rocky9]
     script:
       - dnf install -y python3 # Python 3.9
   ```

2. **EPEL needed**
   ```yaml
   job:
     tags: [rocky8]
     script:
       - dnf install -y epel-release
       - dnf install -y <epel-package>
   ```

### HPA Not Scaling

**Symptoms:**

- High CPU/memory but no scale-up
- Jobs queuing despite low utilization

**Diagnostics:**

```bash
# Check HPA status
kubectl get hpa -n bates-ils-runners

# Detailed HPA info
kubectl describe hpa bates-docker-hpa -n bates-ils-runners

# Check metrics server
kubectl top pods -n bates-ils-runners
```

**Solutions:**

1. **Metrics server not available**

   ```bash
   # Check if metrics-server is running
   kubectl get pods -n kube-system | grep metrics
   ```

2. **Resource requests not set**

   HPA requires resource requests to calculate utilization. Check deployment:

   ```bash
   kubectl get deployment bates-docker -n bates-ils-runners -o yaml | grep -A 10 resources
   ```

### Pod Eviction/OOM

**Symptoms:**

- Pod status: "Evicted" or "OOMKilled"
- Job fails mid-execution

**Solutions:**

1. **Increase job memory limit**

   Contact admin to increase limits in `beehive.tfvars`:

   ```hcl
   nix_job_memory_limit = "16Gi"  # For large Nix builds
   ```

2. **Optimize build**
   ```yaml
   job:
     script:
       # Stream output to avoid buffering
       - make build 2>&1 | tee build.log
       # Clear caches between steps
       - rm -rf node_modules/.cache
   ```

## Debugging Commands

### View Job Pod Logs

```bash
# Find the job pod
kubectl get pods -n bates-ils-runners | grep runner-

# View logs
kubectl logs <pod-name> -n bates-ils-runners -c build

# If pod crashed, view previous logs
kubectl logs <pod-name> -n bates-ils-runners -c build --previous
```

### Check Resource Usage

```bash
# Current usage
kubectl top pods -n bates-ils-runners

# Historical events
kubectl get events -n bates-ils-runners --field-selector reason=OOMKilling
```

### Inspect Runner Configuration

```bash
# Check runner manager config
kubectl exec -n bates-ils-runners deployment/bates-docker -- cat /home/gitlab-runner/.gitlab-runner/config.toml
```

### Test Runner Connectivity

```bash
# Exec into runner manager
kubectl exec -it -n bates-ils-runners deployment/bates-docker -- sh

# Check GitLab connectivity
curl -I https://gitlab.com/api/v4/version
```

## Getting Help

1. Check this documentation first
2. Review GitLab CI/CD documentation: https://docs.gitlab.com/ee/ci/
3. Check runner logs for specific error messages
4. Contact ILS team with:
   - Job URL
   - Error message
   - Runner tags used
   - Output of `kubectl get events -n bates-ils-runners`
