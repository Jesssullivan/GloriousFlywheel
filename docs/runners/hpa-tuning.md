# HPA Tuning Guide

Guide for tuning Horizontal Pod Autoscaler settings for the GitLab runners.

## Overview

Each runner type has an HPA that scales based on:

- CPU utilization (target: 70%)
- Memory utilization (target: 80%)

## Default Configuration

| Runner | Min | Max | Scale Up | Scale Down |
| ------ | --- | --- | -------- | ---------- |
| docker | 1   | 5   | 15s      | 5min       |
| dind   | 1   | 3   | 15s      | 5min       |
| rocky8 | 1   | 3   | 15s      | 5min       |
| rocky9 | 1   | 3   | 15s      | 5min       |
| nix    | 1   | 3   | 15s      | 5min       |

## Checking HPA Status

```bash
# View all HPAs
kubectl get hpa -n bates-ils-runners

# Detailed HPA status
kubectl describe hpa bates-docker-hpa -n bates-ils-runners

# Watch HPA in real-time
kubectl get hpa -n bates-ils-runners -w

# Check metrics
kubectl top pods -n bates-ils-runners
```

## Understanding HPA Metrics

```bash
# Example output
NAME                    REFERENCE             TARGETS           MINPODS   MAXPODS   REPLICAS
bates-docker-hpa        Deployment/bates-...  45%/70%, 30%/80%  1         5         2
```

- `45%/70%`: Current CPU / Target CPU
- `30%/80%`: Current Memory / Target Memory
- `REPLICAS`: Current number of pods

## Tuning Parameters

### Adjusting Targets

Edit `beehive.tfvars`:

```hcl
# Lower targets = more aggressive scaling
hpa_cpu_target    = 60  # Scale up earlier
hpa_memory_target = 70  # Scale up earlier

# Higher targets = less aggressive scaling
hpa_cpu_target    = 80  # Wait longer to scale
hpa_memory_target = 90  # Wait longer to scale
```

### Adjusting Replica Limits

```hcl
# High-volume runner
docker_hpa_min_replicas = 2   # Always have 2 running
docker_hpa_max_replicas = 10  # Allow more scaling

# Low-volume runner
rocky8_hpa_min_replicas = 1
rocky8_hpa_max_replicas = 2
```

### Adjusting Stabilization Windows

```hcl
# Faster scale-up for bursty workloads
hpa_scale_up_window = 0  # No stabilization, scale immediately

# Slower scale-down to handle repeated bursts
hpa_scale_down_window = 600  # 10 minutes
```

## Scaling Behavior

### Scale Up Behavior

Default configuration:

```yaml
scaleUp:
  stabilizationWindowSeconds: 15
  policies:
    - type: Percent
      value: 100 # Can double pods
      periodSeconds: 30
    - type: Pods
      value: 2 # Or add 2 pods
      periodSeconds: 30
  selectPolicy: Max # Use whichever adds more
```

This means:

- Scale up can happen 15 seconds after detection
- Can double pods OR add 2, whichever is more

### Scale Down Behavior

Default configuration:

```yaml
scaleDown:
  stabilizationWindowSeconds: 300 # 5 minutes
  policies:
    - type: Percent
      value: 30 # Remove 30% of pods
      periodSeconds: 60
  selectPolicy: Min # Conservative
```

This means:

- Wait 5 minutes before scaling down
- Remove max 30% of pods per minute
- This protects running jobs

## Workload Patterns

### Bursty Workloads (Push-triggered)

```hcl
# Fast scale-up, slow scale-down
hpa_scale_up_window   = 0
hpa_scale_down_window = 600

docker_hpa_min_replicas = 1
docker_hpa_max_replicas = 10
```

### Steady Workloads (Scheduled)

```hcl
# Moderate scaling
hpa_scale_up_window   = 60
hpa_scale_down_window = 300

docker_hpa_min_replicas = 2
docker_hpa_max_replicas = 4
```

### Peak Hour Patterns

Consider using scheduled scaling with CronJobs:

```yaml
# Scale up before peak hours
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-up-morning
  namespace: bates-ils-runners
spec:
  schedule: "0 8 * * 1-5" # 8 AM weekdays
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: scale
              image: bitnami/kubectl:1.29
              command:
                - kubectl
                - scale
                - deployment/bates-docker
                - --replicas=3
                - -n
                - bates-ils-runners
          restartPolicy: OnFailure
```

## Monitoring HPA

### Prometheus Queries

```promql
# HPA desired replicas vs actual
kube_horizontalpodautoscaler_status_desired_replicas{namespace="bates-ils-runners"}
- kube_horizontalpodautoscaler_status_current_replicas{namespace="bates-ils-runners"}

# HPA utilization ratio
kube_horizontalpodautoscaler_status_current_replicas{namespace="bates-ils-runners"}
/ kube_horizontalpodautoscaler_spec_max_replicas{namespace="bates-ils-runners"}

# Scaling events
changes(kube_horizontalpodautoscaler_status_current_replicas{namespace="bates-ils-runners"}[1h])
```

### Grafana Dashboard

Key panels to include:

1. Replica count over time
2. CPU/Memory utilization vs targets
3. Scaling events timeline
4. Job queue depth (if available)

## Troubleshooting

### HPA Not Scaling Up

1. **Check metrics-server**

   ```bash
   kubectl get pods -n kube-system | grep metrics
   kubectl top pods -n bates-ils-runners
   ```

2. **Check resource requests**

   ```bash
   kubectl get deployment bates-docker -n bates-ils-runners -o yaml | grep -A5 resources
   ```

   HPA requires resource requests to calculate utilization.

3. **Check target values**
   ```bash
   kubectl describe hpa bates-docker-hpa -n bates-ils-runners | grep -A5 Metrics
   ```

### HPA Scaling Too Aggressively

1. **Increase targets**

   ```hcl
   hpa_cpu_target    = 80
   hpa_memory_target = 90
   ```

2. **Increase stabilization window**

   ```hcl
   hpa_scale_up_window = 60  # Wait 1 minute
   ```

3. **Check for noisy metrics**
   ```bash
   kubectl top pods -n bates-ils-runners
   # Run multiple times to see variance
   ```

### HPA Not Scaling Down

1. **Check stabilization window**
   The default 5-minute window means it won't scale down quickly.

2. **Check minimum replicas**

   ```bash
   kubectl get hpa bates-docker-hpa -n bates-ils-runners -o yaml | grep minReplicas
   ```

3. **Check for stuck pods**
   ```bash
   kubectl get pods -n bates-ils-runners | grep -v Running
   ```

## Best Practices

1. **Start conservative**: Begin with default settings and adjust based on data

2. **Monitor before tuning**: Collect at least a week of data before making changes

3. **Test in off-hours**: Make HPA changes during low-activity periods

4. **Use PDB**: Always pair HPA with Pod Disruption Budget to protect running jobs

5. **Document changes**: Track HPA tuning decisions in commit messages

## Applying Changes

After editing `beehive.tfvars`:

```bash
cd tofu/stacks/bates-ils-runners
just plan
just apply
```

Or from the root:

```bash
just ils-runners-plan
just ils-runners-apply
```
