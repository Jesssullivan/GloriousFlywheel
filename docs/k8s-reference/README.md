# Kubernetes Reference Manifests

This directory contains reference Kubernetes manifests for documentation purposes.

**These files are NOT used for deployment.** All Kubernetes resources are generated and managed via OpenTofu in `tofu/stacks/attic/`.

## Purpose

- Serve as reference documentation for the Kubernetes resource structure
- Provide examples for manual debugging or testing
- Show the expected format of secrets and configurations

## Actual Deployment

For actual deployments, use:

```bash
cd tofu/stacks/attic
tofu init
tofu plan -var-file=beehive.tfvars  # or rigel.tfvars
tofu apply -var-file=<envfile>.tfvars
```

Or use GitLab CI/CD:

- Push to feature branch: Review environment on beehive
- Merge to main: Staging on rigel
- Tag with semver (vX.Y.Z): Production on rigel
