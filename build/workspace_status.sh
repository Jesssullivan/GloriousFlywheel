#!/usr/bin/env bash
# Workspace status script for Bazel stamping
# Provides build metadata for container images and artifacts

set -euo pipefail

# Git information
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "STABLE_GIT_COMMIT $(git rev-parse HEAD)"
  echo "STABLE_GIT_SHORT_COMMIT $(git rev-parse --short HEAD)"
  echo "STABLE_GIT_BRANCH $(git rev-parse --abbrev-ref HEAD)"

  # Check for uncommitted changes
  if git diff-index --quiet HEAD --; then
    echo "STABLE_GIT_DIRTY false"
  else
    echo "STABLE_GIT_DIRTY true"
  fi

  # Latest tag if available
  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    echo "STABLE_GIT_TAG $(git describe --tags --abbrev=0)"
  fi
fi

# Build timestamp
echo "STABLE_BUILD_TIME $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# CI information
if [ -n "${CI:-}" ]; then
  echo "STABLE_CI true"
  echo "STABLE_CI_PIPELINE_ID ${CI_PIPELINE_ID:-unknown}"
  echo "STABLE_CI_JOB_ID ${CI_JOB_ID:-unknown}"
else
  echo "STABLE_CI false"
fi

# Nix store path (if building with Nix)
if [ -n "${NIX_STORE:-}" ]; then
  echo "STABLE_NIX_STORE $NIX_STORE"
fi
