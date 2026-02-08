# Load Testing Guide

Guide for load testing the GitLab Runners infrastructure.

## Test Scenarios

### Scenario 1: Burst Load

Simulate 20 simultaneous jobs to test scale-up behavior.

```yaml
# .gitlab-ci.yml for burst test
stages:
  - burst

.burst-job:
  stage: burst
  script:
    - echo "Job $CI_JOB_ID started at $(date)"
    - sleep 60 # Simulate 1-minute job
    - echo "Job $CI_JOB_ID completed"

burst-01: { extends: .burst-job, tags: [docker] }
burst-02: { extends: .burst-job, tags: [docker] }
burst-03: { extends: .burst-job, tags: [docker] }
burst-04: { extends: .burst-job, tags: [docker] }
burst-05: { extends: .burst-job, tags: [docker] }
burst-06: { extends: .burst-job, tags: [docker] }
burst-07: { extends: .burst-job, tags: [docker] }
burst-08: { extends: .burst-job, tags: [docker] }
burst-09: { extends: .burst-job, tags: [docker] }
burst-10: { extends: .burst-job, tags: [docker] }
burst-11: { extends: .burst-job, tags: [docker] }
burst-12: { extends: .burst-job, tags: [docker] }
burst-13: { extends: .burst-job, tags: [docker] }
burst-14: { extends: .burst-job, tags: [docker] }
burst-15: { extends: .burst-job, tags: [docker] }
burst-16: { extends: .burst-job, tags: [docker] }
burst-17: { extends: .burst-job, tags: [docker] }
burst-18: { extends: .burst-job, tags: [docker] }
burst-19: { extends: .burst-job, tags: [docker] }
burst-20: { extends: .burst-job, tags: [docker] }
```

**Expected Behavior:**

- HPA scales docker runner to max (5 replicas)
- All jobs complete within ~5 minutes
- No jobs fail due to infrastructure

### Scenario 2: Sustained Load

Simulate 10 jobs/minute for 30 minutes.

```bash
#!/bin/bash
# sustained-load.sh
for i in $(seq 1 30); do
  for j in $(seq 1 10); do
    curl -X POST \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "https://gitlab.com/api/v4/projects/$PROJECT_ID/trigger/pipeline" \
      -F "ref=main" \
      -F "token=$TRIGGER_TOKEN" \
      -F "variables[TEST_ID]=$i-$j" &
  done
  sleep 60
done
wait
```

**Expected Behavior:**

- Runners stabilize at mid-scale
- No job queue backlog
- Memory/CPU stay below 90%

### Scenario 3: Mixed Workload

Test all runner types simultaneously.

```yaml
stages:
  - test

test-docker:
  tags: [docker, linux]
  script:
    - apk add --no-cache curl
    - curl -I https://example.com

test-dind:
  tags: [dind, privileged]
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://localhost:2375
    DOCKER_TLS_CERTDIR: ""
  script:
    - docker pull alpine:latest
    - docker images

test-rocky8:
  tags: [rocky8]
  script:
    - cat /etc/redhat-release
    - dnf list installed | head -20

test-rocky9:
  tags: [rocky9]
  script:
    - cat /etc/redhat-release
    - dnf list installed | head -20

test-nix:
  tags: [nix, flakes]
  script:
    - nix --version
    - nix build nixpkgs#hello
    - ./result/bin/hello
```

**Expected Behavior:**

- Each runner type handles its jobs
- No cross-contamination
- All jobs pass

### Scenario 4: Idle Behavior

Test scale-down after load.

1. Run burst test
2. Wait 10 minutes
3. Verify all runners scaled to minimum

```bash
# Check scale-down
watch -n 30 'kubectl get hpa -n {org}-runners'
```

**Expected Behavior:**

- All HPAs show 1 replica after 5-10 minutes
- No stuck pods

## Monitoring During Tests

### Real-time Monitoring

```bash
# Terminal 1: HPA status
watch -n 5 'kubectl get hpa -n {org}-runners'

# Terminal 2: Pod count
watch -n 5 'kubectl get pods -n {org}-runners | wc -l'

# Terminal 3: Resource usage
watch -n 10 'kubectl top pods -n {org}-runners'

# Terminal 4: Events
kubectl get events -n {org}-runners -w
```

### Prometheus Queries

```promql
# Job queue depth
gitlab_runner_jobs{state="running"}

# Scaling activity
changes(kube_horizontalpodautoscaler_status_current_replicas{namespace="{org}-runners"}[5m])

# Resource utilization
avg(container_cpu_usage_seconds_total{namespace="{org}-runners"})
```

## Success Criteria

| Metric            | Target          | How to Measure       |
| ----------------- | --------------- | -------------------- |
| Job start latency | < 30s P95       | GitLab job metrics   |
| Scale-up time     | < 60s           | HPA event timestamps |
| Scale-down time   | 5-10 min        | HPA event timestamps |
| Job success rate  | > 99%           | GitLab CI analytics  |
| Memory usage      | < 85% peak      | kubectl top          |
| CPU usage         | < 80% sustained | kubectl top          |

## Post-Test Analysis

### Collect Metrics

```bash
# Export HPA events
kubectl get events -n {org}-runners \
  --field-selector reason=SuccessfulRescale \
  -o json > hpa-events.json

# Export pod metrics (requires metrics-server)
kubectl top pods -n {org}-runners --no-headers \
  > pod-metrics-$(date +%Y%m%d-%H%M).txt
```

### GitLab Analytics

1. Go to **CI/CD > Analytics**
2. Check:
   - Pipeline duration trends
   - Job wait times
   - Failure rates

### Identify Issues

Common issues to look for:

- Jobs stuck in pending (not enough runners)
- OOM kills (memory limits too low)
- Slow scale-up (stabilization window too long)
- Thrashing (targets too sensitive)

## Tuning Based on Results

### If jobs wait too long:

```hcl
# Increase replicas
docker_hpa_max_replicas = 10

# Faster scale-up
hpa_scale_up_window = 0

# Lower CPU target
hpa_cpu_target = 60
```

### If HPA thrashes:

```hcl
# Increase stabilization windows
hpa_scale_up_window   = 60
hpa_scale_down_window = 600

# Higher targets
hpa_cpu_target    = 80
hpa_memory_target = 85
```

### If OOM kills occur:

```hcl
# Increase job memory
docker_job_memory_limit = "4Gi"

# Or reduce concurrency
docker_concurrent_jobs = 4
```

## Automated Load Test Script

```bash
#!/bin/bash
# load-test.sh - Automated load testing

NAMESPACE="{org}-runners"
DURATION_MINUTES=30
JOBS_PER_MINUTE=10

echo "Starting load test: $JOBS_PER_MINUTE jobs/min for $DURATION_MINUTES minutes"
echo "Namespace: $NAMESPACE"
echo ""

# Baseline metrics
echo "Baseline HPA status:"
kubectl get hpa -n $NAMESPACE
echo ""

# Start monitoring in background
kubectl get events -n $NAMESPACE -w > events.log &
EVENTS_PID=$!

# Run load
for i in $(seq 1 $DURATION_MINUTES); do
  echo "Minute $i: Triggering $JOBS_PER_MINUTE jobs..."
  for j in $(seq 1 $JOBS_PER_MINUTE); do
    # Trigger pipeline via API (implement your trigger)
    # curl ... &
    echo "  Job $i-$j triggered"
  done

  # Snapshot metrics
  echo "HPA status at minute $i:"
  kubectl get hpa -n $NAMESPACE --no-headers

  sleep 60
done

# Stop monitoring
kill $EVENTS_PID 2>/dev/null

# Final metrics
echo ""
echo "Final HPA status:"
kubectl get hpa -n $NAMESPACE

echo ""
echo "Load test complete. Check events.log for scaling events."
```

## Cleanup After Testing

```bash
# Cancel any pending pipelines
glab ci list --status running -P $PROJECT_ID

# Clean up test artifacts
kubectl delete pods -n {org}-runners --field-selector=status.phase==Succeeded

# Reset any manual scaling
kubectl scale deployment -n {org}-runners --all --replicas=1
```
