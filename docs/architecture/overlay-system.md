---
title: Overlay System
order: 20
---

# Overlay System

This document describes the mechanics of `build/overlay.bzl` and
`build/extensions.bzl`, which together implement the symlink-merge
overlay that combines upstream and private files into a single Bazel
repository.

## Purpose

Institutional deployments need to add private configuration (tfvars,
secrets references, environment-specific configs) and occasionally
replace upstream defaults. The overlay system provides this without
forking: the overlay repository contains only the delta, and the merge
happens at build time.

## How the Merge Works

The overlay is implemented as a Bazel repository rule. At a high level:

1. The rule receives two directory paths: the upstream source tree
   (resolved via `bazel_dep` + `local_path_override`) and the overlay
   source tree (the overlay repository root).
2. It walks both trees recursively, collecting every file path relative
   to the root.
3. For each file, it creates a symlink in the output repository
   (`@attic_merged`):
   - If the file exists only in upstream, the symlink points to the
     upstream copy.
   - If the file exists only in the overlay, the symlink points to the
     overlay copy.
   - If the file exists in both trees, the symlink points to the
     **overlay copy**. This is the private-wins-on-conflict rule.
4. The resulting `@attic_merged` repository looks like a single coherent
   source tree and can be built with normal Bazel commands.

## Private-Wins-on-Conflict Semantics

The conflict resolution is intentionally simple: the overlay always wins.
There is no file-level merging, no patch application, and no conditional
logic. If an overlay provides `tofu/stacks/attic/terraform.tfvars`, that
file completely replaces the upstream version of the same path.

This makes the system predictable. To understand what Bazel sees for any
given file, check whether the overlay contains it. If yes, that version
is used. If no, the upstream version is used.

## File Tree Watching with ctx.watch_tree()

Bazel 7.1 introduced `ctx.watch_tree()`, which allows repository rules
to declare file-system watches on directories. The overlay rule registers
watches on both:

- The upstream source tree
- The overlay source tree

When any file in either tree is created, modified, or deleted, Bazel
marks the `@attic_merged` repository as stale. The next `bazel build`
command will re-execute the repository rule, regenerating all symlinks.
This means developers working on either the upstream or overlay codebase
see their changes reflected immediately without running any manual
invalidation commands.

## What Overlays Typically Add

Overlays are used for files that are specific to a deployment and should
not be published upstream:

- **tfvars files** -- variable values for OpenTofu stacks
  (`cluster_context`, `gitlab_token`, environment-specific sizing)
- **Stack configurations** -- additional stacks that exist only in one
  deployment (e.g., `bates-ils-runners`)
- **Environment configs** -- `organization.yaml` or similar files that
  define the institutional identity
- **CI pipeline definitions** -- `.gitlab-ci.yml` tailored to the
  institution's GitLab setup

Overlays can also **replace** upstream defaults. For example, an overlay
might provide its own `tofu/stacks/attic/main.tf` if the upstream version
does not support a required backend configuration.

## Build Targets from the Merged Repository

Once `@attic_merged` exists, the overlay `BUILD.bazel` can define aliases
and aggregation targets that reference it:

- `bazel build //...` builds all overlay and upstream targets.
- `bazel build //:deployment_bundle` creates a `pkg_tar` of overlay
  configs combined with upstream artifacts.
- `bazel build //:validate_modules` validates all upstream OpenTofu
  modules via `@attic-iac//tofu/modules:all_validate`.
- `bazel build //:app` builds the SvelteKit application from upstream
  source.

## Related Documents

- [Bzlmod Topology](bzlmod-topology.md) -- the module dependency
  structure that feeds into the overlay
- [Multi-Repo Layout](multi-repo-layout.md) -- where the upstream and
  overlay repositories are hosted
