---
title: HPA Tuning
order: 40
---

# HPA Tuning

Each runner type has an independent HorizontalPodAutoscaler (HPA) that
manages replica count based on CPU utilization.

## Default Configuration

| Parameter | Value |
|-----------|-------|
| Minimum replicas | 1 |
| Maximum replicas | 5 |
| Scale-up stabilization window | 15 seconds |
| Scale-down stabilization window | 5 minutes |
| Target metric | CPU utilization at 70% |

The asymmetric stabilization windows are intentional. The short scale-up
window allows the cluster to respond quickly to load spikes. The longer
scale-down window prevents thrashing when load fluctuates around the
threshold.

## Overriding Defaults

HPA parameters are configured per runner type in `organization.yaml`. To
change the replica range or stabilization windows for a specific runner,
edit the corresponding entry and run `tofu apply` from the overlay.

## Monitoring

Check HPA status for all runners in the namespace:

```bash
kubectl get hpa -n bates-ils-runners
```

This shows current and desired replica counts, current CPU utilization, and
whether the autoscaler is actively scaling.

For more detail on a specific runner:

```bash
kubectl describe hpa runner-docker -n bates-ils-runners
```

## Scaling Considerations

- **docker**: Scales frequently under mixed workloads. The default range
  (1--5) is usually sufficient.
- **dind**: Container builds are bursty. If builds queue during peak hours,
  consider increasing the maximum.
- **rocky8/rocky9**: Typically low utilization. Minimum of 1 keeps a warm
  pod available.
- **nix**: CPU-intensive builds can saturate a pod quickly. Monitor
  utilization and adjust the maximum if builds are queuing.

## Related

- [Runbook](runbook.md) -- procedures for scaling up and emergency stop
- [Troubleshooting](troubleshooting.md) -- diagnosing pod crashes from
  resource pressure
