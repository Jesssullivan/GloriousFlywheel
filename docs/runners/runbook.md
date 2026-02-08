---
title: Runbook
order: 70
---

# Runbook

Operational procedures for managing the runner infrastructure.

## Scaling Up

To increase the maximum number of replicas for a runner type:

1. Edit the HPA `max` value for the target runner in `organization.yaml`.
2. Apply the change:
   ```bash
   tofu apply
   ```
3. Verify the new HPA configuration:
   ```bash
   kubectl get hpa -n bates-ils-runners
   ```

See [HPA Tuning](hpa-tuning.md) for details on stabilization windows and
scaling behavior.

## Rotating Runner Tokens

To rotate the GitLab runner registration token:

1. Delete the Kubernetes Secret containing the current token:
   ```bash
   kubectl delete secret runner-token-TYPE -n bates-ils-runners
   ```
2. Re-apply to recreate the secret with a new token:
   ```bash
   tofu apply
   ```
3. Runner pods will pick up the new token on their next restart.

## Adding a New Runner Type

1. Add the new runner definition to `organization.yaml` with its
   configuration (base image, tags, resource limits, HPA settings).
2. Create corresponding `tfvars` entries in the overlay for the new
   runner type.
3. Apply:
   ```bash
   tofu apply
   ```
4. Verify the new runner appears in the GitLab group runner list.

## Emergency Stop

To immediately stop all runners of a specific type:

**Option A** -- Scale HPA to zero:
```bash
kubectl scale hpa runner-TYPE --replicas=0 -n bates-ils-runners
```

**Option B** -- Delete the runner deployment:
```bash
kubectl delete deployment runner-TYPE -n bates-ils-runners
```

Note: Option B requires a `tofu apply` to recreate the deployment when
service is restored. Option A can be reversed by setting replicas back to
the desired minimum.

## Log Collection

View logs for all pods of a specific runner type:

```bash
kubectl logs -n bates-ils-runners -l app=runner-TYPE
```

Follow logs in real time:

```bash
kubectl logs -n bates-ils-runners -l app=runner-TYPE --follow
```

## Health Check

From the overlay repository, run the health check target:

```bash
just ils-runners-health
```

This verifies that all runner types have at least one healthy pod and that
the runners are registered with GitLab.

## Manual Status Check

To inspect the full state of the runner namespace:

```bash
kubectl get pods,hpa,deployments -n bates-ils-runners
```

For a specific runner type:

```bash
kubectl get pods -n bates-ils-runners -l app=runner-docker
kubectl describe hpa runner-docker -n bates-ils-runners
```

## Related

- [HPA Tuning](hpa-tuning.md) -- autoscaler configuration details
- [Troubleshooting](troubleshooting.md) -- diagnosing common issues
- [Security Model](security-model.md) -- access controls and secrets
