# Compatibility shell for non-flake Nix users
# Usage: nix-shell

{ pkgs ? import <nixpkgs> { } }:

let
  compat = import ./default.nix { inherit pkgs; };
in
  compat.shell or (pkgs.mkShell {
    # Fallback shell if flake-compat fails
    name = "attic-cache-fallback";

    packages = with pkgs; [
      kubectl
      kubernetes-helm
      opentofu
      jq
      yq-go
      git
    ];

    shellHook = ''
      echo "WARNING: Running fallback shell (flake-compat not available)"
      echo "For full functionality, use: nix develop"
    '';
  })
