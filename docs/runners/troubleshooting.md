---
title: Troubleshooting
order: 60
---

# Troubleshooting

Common issues with the runner infrastructure and how to resolve them.

## Runner Not Registering

**Symptom**: Runner pod starts but does not appear in the GitLab group
runner list.

**Causes and fixes**:

- **Invalid runner token**: Verify the Kubernetes Secret containing the
  registration token exists and is current. Delete the secret and run
  `tofu apply` to recreate it.
- **Group access**: Confirm that the service account or user associated with
  the token has access to the target GitLab group.
- **Token auto-creation**: Automatic runner token creation requires the
  **Owner** role on the GitLab group. If the deploying user does not have
  Owner, token creation will fail silently. Verify role assignment in
  GitLab group settings.

## Pods Crashing (OOMKilled)

**Symptom**: Runner pods restart repeatedly. `kubectl describe pod` shows
`OOMKilled` as the termination reason.

**Fix**: Increase the memory limit for the affected runner type in
`organization.yaml` and run `tofu apply`. See [HPA Tuning](hpa-tuning.md)
for resource limit configuration.

Common memory-hungry workloads:
- `dind`: Container builds with large build contexts.
- `nix`: Derivations that compile large packages from source.

## Cache Misses on Nix Runner

**Symptom**: Nix builds download or compile everything from scratch despite
previous builds having populated the cache.

**Causes and fixes**:

- **ATTIC_SERVER not set**: Verify the environment variable is present in
  the runner pod. Check that the Kubernetes Secret for Attic credentials
  exists in the `{org}-runners` namespace.
- **Attic service unreachable**: Confirm the Attic cache service is running
  in the `attic-cache-dev` namespace. Test connectivity from a runner pod
  with `curl $ATTIC_SERVER`.
- **Cache name mismatch**: Verify `ATTIC_CACHE` matches the cache name
  used in `attic push` commands.

## TOML Configuration Gotchas

The GitLab Runner TOML configuration has several pitfalls in Runner 17.x:

- **Resource limits must be flat keys**: Values like `cpu_limit`,
  `memory_limit`, `cpu_request`, and `memory_request` must be specified as
  flat keys in the `[[runners.kubernetes]]` section. Do not nest them inside
  a TOML table.
- **pod_spec.containers type mismatch**: Using `pod_spec` with a
  `containers` field causes a type mismatch error in Runner 17.x. Instead,
  use `environment = [...]` on the `[[runners]]` section to inject
  environment variables.

## Runner Pods Pending

**Symptom**: Pods stay in `Pending` state and are not scheduled.

**Causes and fixes**:

- **Insufficient cluster resources**: Check node capacity with
  `kubectl describe nodes`. The cluster may need more nodes or the runner
  resource requests may be too high.
- **HPA at maximum**: If all replicas are running and jobs are still
  queuing, increase the HPA maximum. See [HPA Tuning](hpa-tuning.md).

## Related

- [Runbook](runbook.md) -- operational procedures for common tasks
- [Security Model](security-model.md) -- access and permission details
