# Example Flake with Attic Cache Configuration
# =============================================
#
# This flake demonstrates how to configure Attic as a binary cache substituter.
# Users who run `nix build` in this project will be prompted to trust the cache.
{
  description = "Example project using Attic binary cache";

  # Configure the Attic cache as a substituter
  # Users will be prompted to trust this cache on first use
  nixConfig = {
    extra-substituters = [
      "https://nix-cache.example.com/main"
    ];
    extra-trusted-public-keys = [
      # Replace with actual public key from:
      # curl https://nix-cache.example.com/main/nix-cache-info
      "main:YOUR_PUBLIC_KEY_HERE"
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        # Development shell with Attic client
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Your development tools here
            gnumake
            git

            # Attic client for cache management
            attic-client
          ];

          shellHook = ''
            echo "Development environment ready"
            echo ""
            echo "Attic cache commands:"
            echo "  attic login production https://nix-cache.example.com"
            echo "  attic use main          # Configure as substituter"
            echo "  attic push main result  # Push build results"
            echo ""
          '';
        };

        # Example package
        packages.default = pkgs.hello;

        # Example check
        checks.default = self.packages.${system}.default;
      }
    );
}
