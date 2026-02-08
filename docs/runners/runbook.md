# GitLab Runner Pool - Operational Runbook

Operational procedures for the GitLab runner fleet deployed in
the `gitlab-runners` namespace. Five runner types: docker, dind,
rocky8, rocky9, nix. Managed via OpenTofu + Helm.

---

## Alert Response Procedures

### RunnerResourceQuotaExhausted

Fires when namespace resource quota utilization exceeds 90%.

1. Check current quota usage:

   ```bash
   kubectl get resourcequota runner-quota -n bates-ils-runners -o wide
   ```

2. Identify which pods are consuming the most resources:

   ```bash
   kubectl top pods -n bates-ils-runners --sort-by=cpu
   kubectl top pods -n bates-ils-runners --sort-by=memory
   ```

3. Resolution options:
   - **Increase quota**: edit `resource_quota_cpu` / `resource_quota_memory`
     in the environment tfvars, then `just ils-runners-plan` and
     `just ils-runners-apply`.
   - **Reduce load**: identify resource-heavy jobs in GitLab CI and
     optimize or move them to a dedicated runner type.
   - **Evict idle pods**: if HPA has scaled beyond need, lower
     `hpa_max_replicas` temporarily.

### RunnerNamespaceLeaked

Fires when orphaned `ci-job-*` namespaces exist for more than 2 hours.

1. List orphaned namespaces:

   ```bash
   kubectl get ns | grep ci-job-
   ```

2. The cleanup CronJob should handle this automatically. Verify it ran:

   ```bash
   kubectl get cronjob -n bates-ils-runners
   kubectl get jobs -n bates-ils-runners --sort-by=.status.startTime
   ```

3. If the CronJob failed or has not run, delete manually:

   ```bash
   kubectl delete ns ci-job-XXXX
   ```

4. If namespaces keep leaking, check runner executor config -- the
   `namespace_overwrite_allowed` setting and cleanup policies in
   `values.yaml`.

### RunnerJobQueueBacklog

Fires when pending job count exceeds 10 for more than 5 minutes.

1. Check HPA status for the affected runner type:

   ```bash
   kubectl get hpa -n bates-ils-runners
   ```

2. Verify runner pods are healthy and accepting jobs:

   ```bash
   kubectl get pods -n bates-ils-runners -l app=gitlab-runner
   kubectl logs -n bates-ils-runners -l app=gitlab-runner --tail=50
   ```

3. Resolution options:
   - **Increase max replicas**: raise `hpa_max_replicas` in tfvars,
     plan and apply.
   - **Check GitLab connectivity**: runner pods may have lost contact
     with GitLab. Check logs for registration errors.
   - **Check resource quota**: the HPA may want to scale but quota
     blocks new pods (see RunnerResourceQuotaExhausted above).

---

## Routine Operations

### Scaling Runners

Adjust HPA bounds in the environment tfvars file:

```hcl
docker_hpa_min_replicas = 2
docker_hpa_max_replicas = 8
```

Then apply:

```bash
just ils-runners-plan
just ils-runners-apply
```

Verify:

```bash
kubectl get hpa -n bates-ils-runners
```

### Token Rotation

Runner tokens are auto-managed via the `gitlab_user_runner` resource.
To force a rotation:

```bash
# Taint the token resource for the target runner
tofu taint 'module.bates_docker.gitlab_user_runner.this'
just ils-runners-plan
just ils-runners-apply
```

The Helm release will pick up the new token on the next pod restart.

### Adding a Runner Type

1. Add a new module block in `main.tf`:

   ```hcl
   module "bates_newtype" {
     source = "../../modules/gitlab-runner"
     # ... variables
   }
   ```

2. Add corresponding variables to `variables.tf` and set values in the
   environment tfvars.

3. Plan and apply:

   ```bash
   just ils-runners-plan
   just ils-runners-apply
   ```

### Updating Runner Version

Change `chart_version` in the module call or module default:

```hcl
chart_version = "0.72.0"
```

Plan and apply. The Helm release will perform a rolling update.

---

## Emergency Procedures

### Kill All Running Jobs

Immediately terminate all runner pods (jobs will be retried by GitLab):

```bash
kubectl delete pods -n bates-ils-runners -l app=gitlab-runner --grace-period=0
```

### Scale to Zero

Stop all runners without destroying infrastructure:

1. Set in tfvars:

   ```hcl
   docker_hpa_min_replicas = 0
   dind_hpa_min_replicas   = 0
   rocky8_hpa_min_replicas = 0
   rocky9_hpa_min_replicas = 0
   nix_hpa_min_replicas    = 0
   ```

2. Apply:

   ```bash
   just ils-runners-plan
   just ils-runners-apply
   ```

### Disable a Single Runner Type

Set the deploy flag to false in tfvars:

```hcl
deploy_dind_runner = false
```

Plan and apply. The Helm release and associated resources will be
destroyed. Re-enable by setting back to `true`.

### Namespace Cleanup

Remove leftover test or CI namespaces:

```bash
# Remove load-test namespaces
kubectl delete ns -l app=loadtest

# Trigger cleanup CronJob manually
kubectl create job --from=cronjob/ns-cleanup manual-cleanup -n bates-ils-runners
```

---

## Health Checks

### Quick Status

```bash
just ils-runners-status
```

Shows pod counts and HPA state for all runner types.

### Full Health Check

```bash
just ils-runners-health
```

Runs the comprehensive health check (calls `scripts/runner-health-check.sh`).

### Detailed Diagnostics

```bash
scripts/runner-health-check.sh
```

Per-runner diagnostics including pod status, HPA state, metrics
endpoint availability, PDB/ServiceMonitor/NetworkPolicy counts, and
resource quota utilization. Exits non-zero if any runner is down.

### Manual Spot Checks

```bash
# Pod overview
kubectl get pods -n bates-ils-runners -o wide

# HPA state
kubectl get hpa -n bates-ils-runners

# Recent events (useful for crash loops or scheduling failures)
kubectl get events -n bates-ils-runners --sort-by=.lastTimestamp | tail -20

# Runner logs
kubectl logs -n bates-ils-runners -l release=bates-docker --tail=100
```
