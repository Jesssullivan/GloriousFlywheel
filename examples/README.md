# Examples

Copy-paste templates for integrating with GloriousFlywheel infrastructure.

## Available Examples

| Example | Description |
|---------|-------------|
| [gitlab](gitlab/) | GitLab CI pipeline using Attic Nix binary cache (build, check, test) |
| [flake](flake/) | Reference `flake.nix` with Attic cache configured as a substituter |

## Runner Tags

When using the shared runner pool, add `tags:` to route jobs to the right runner:

```yaml
default:
  tags: [docker]       # General CI (Python, Node, Go)

build:container:
  tags: [dind]         # Docker-in-Docker (container builds, Molecule)

build:nix:
  tags: [nix]          # Nix builds with Attic cache

package:el8:
  tags: [rocky8]       # RHEL 8 packaging

package:el9:
  tags: [rocky9]       # RHEL 9 packaging
```

Jobs without `tags:` run on GitLab SaaS shared runners.

See [Self-Service Enrollment](../docs/runners/self-service-enrollment.md) for full details.
