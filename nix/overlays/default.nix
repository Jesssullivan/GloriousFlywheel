# Nix overlays for Attic Cache
# These overlays can be imported into other flakes or configurations

{
  # Default overlay - adds attic packages to nixpkgs
  default = _final: _prev: {
    # Attic packages will be added here when needed
    # This overlay is primarily a placeholder for future customizations
  };

  # Overlay for adding custom tools
  tools = final: _prev: {
    # Custom wrapper scripts or tools can be defined here
    attic-push-ci = final.writeShellScriptBin "attic-push-ci" ''
      #!/usr/bin/env bash
      # CI-friendly wrapper for pushing to Attic cache
      set -euo pipefail

      CACHE_NAME="''${ATTIC_CACHE_NAME:-main}"
      PATHS="$@"

      if [ -z "$PATHS" ]; then
        echo "Usage: attic-push-ci <store-paths...>"
        exit 1
      fi

      echo "Pushing to cache: $CACHE_NAME"
      ${final.lib.getExe final.attic-client} push "$CACHE_NAME" $PATHS
    '';
  };

  # Overlay for Kubernetes tooling
  k8s = final: _prev: {
    # Kubernetes manifest validation
    k8s-validate = final.writeShellScriptBin "k8s-validate" ''
      #!/usr/bin/env bash
      # Validate Kubernetes manifests
      set -euo pipefail

      MANIFESTS="''${1:-k8s/}"

      echo "Validating Kubernetes manifests in: $MANIFESTS"
      ${final.kubectl}/bin/kubectl apply --dry-run=client -f "$MANIFESTS" 2>&1
    '';
  };
}
