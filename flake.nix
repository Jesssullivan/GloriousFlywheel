{
  description = "Attic Nix Binary Cache - Civo Kubernetes Deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    # Attic binary cache server
    # Don't follow nixpkgs - Attic needs its own nixpkgs with compatible Rust/Nix versions
    attic.url = "github:zhaofengli/attic";

    # OCI image building without Docker daemon
    # Don't follow nixpkgs - nix2container needs its own newer nixpkgs for Go 1.24
    nix2container.url = "github:nlewo/nix2container";

    # Treefmt for consistent formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, attic, nix2container, treefmt-nix }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };

          n2c = nix2container.packages.${system}.nix2container;

          # Treefmt configuration
          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs = {
              nixpkgs-fmt.enable = true;
              prettier.enable = true;
              shfmt.enable = true;
            };
          };

          # Attic packages from upstream
          atticServer = attic.packages.${system}.attic-server or attic.packages.${system}.default;
          atticClient = attic.packages.${system}.attic or attic.packages.${system}.attic-client;

          # Bazel wrapper that calls bazelisk (most users expect 'bazel' command)
          bazelWrapper = pkgs.writeShellScriptBin "bazel" ''
            exec ${pkgs.bazelisk}/bin/bazelisk "$@"
          '';

          # Development tools
          devTools = with pkgs; [
            # Kubernetes tooling
            kubectl
            kubernetes-helm
            k9s
            kustomize

            # Infrastructure as Code
            opentofu
            civo

            # Attic client
            atticClient

            # Nix tooling
            nix-prefetch-git
            nix-tree
            nixpkgs-fmt
            statix
            deadnix

            # Build tooling
            bazel-buildtools
            bazelisk
            bazelWrapper # Provides 'bazel' command that wraps bazelisk

            # Container tooling
            skopeo
            dive

            # Development utilities
            jq
            yq-go
            direnv
            nix-direnv
            git
            gnumake

            # PostgreSQL client for debugging
            postgresql
          ];

          # OCI image for Attic server
          atticServerImage = n2c.buildImage {
            name = "attic-server";
            tag = "latest";

            # Use a minimal base image
            copyToRoot = pkgs.buildEnv {
              name = "attic-server-root";
              paths = [
                atticServer
                pkgs.cacert
                pkgs.tzdata
              ];
              pathsToLink = [ "/bin" "/etc" "/share" ];
            };

            config = {
              Entrypoint = [ "${atticServer}/bin/atticd" ];
              Cmd = [ "--config" "/etc/attic/server.toml" "--mode" "api-server" ];
              Env = [
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "TZ=UTC"
              ];
              ExposedPorts = {
                "8080/tcp" = { };
              };
              Labels = {
                "org.opencontainers.image.source" = "https://gitlab.com/tinyland/infra/attic-cache";
                "org.opencontainers.image.description" = "Attic Nix Binary Cache Server";
                "org.opencontainers.image.licenses" = "Apache-2.0";
              };
            };
          };

          # OCI image for Attic garbage collector
          atticGCImage = n2c.buildImage {
            name = "attic-gc";
            tag = "latest";

            copyToRoot = pkgs.buildEnv {
              name = "attic-gc-root";
              paths = [
                atticServer
                pkgs.cacert
                pkgs.tzdata
              ];
              pathsToLink = [ "/bin" "/etc" "/share" ];
            };

            config = {
              Entrypoint = [ "${atticServer}/bin/atticd" ];
              Cmd = [ "--config" "/etc/attic/server.toml" "--mode" "garbage-collector" ];
              Env = [
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "TZ=UTC"
              ];
              Labels = {
                "org.opencontainers.image.source" = "https://gitlab.com/tinyland/infra/attic-cache";
                "org.opencontainers.image.description" = "Attic Nix Binary Cache Garbage Collector";
                "org.opencontainers.image.licenses" = "Apache-2.0";
              };
            };
          };

        in
        {
          # Development shell with all required tools
          devShells.default = pkgs.mkShell {
            name = "attic-cache-dev";
            packages = devTools;

            shellHook = ''
              echo "Attic Cache Development Environment"
              echo "===================================="
              echo ""
              echo "Available tools:"
              echo "  kubectl, helm, k9s    - Kubernetes management"
              echo "  tofu                  - Infrastructure as Code"
              echo "  civo                  - Civo CLI"
              echo "  attic                 - Attic client"
              echo "  bazelisk              - Bazel launcher"
              echo ""
              echo "Common commands:"
              echo "  nix build .#container       - Build Attic OCI image"
              echo "  nix build .#attic-client    - Build Attic client"
              echo "  nix flake check             - Run all checks"
              echo "  bazel build //...           - Build all Bazel targets"
              echo ""

              # Set up direnv if available
              if command -v direnv &> /dev/null; then
                eval "$(direnv hook bash 2>/dev/null || direnv hook zsh 2>/dev/null || true)"
              fi

              # Configure kubectl context hint
              if [ -n "$KUBECONFIG" ]; then
                echo "KUBECONFIG: $KUBECONFIG"
              fi
            '';

            # Environment variables
            ATTIC_CACHE_URL = "https://nix-cache.fuzzy-dev.tinyland.dev";
          };

          # Packages
          packages = {
            default = atticClient;
            attic-server = atticServer;
            attic-client = atticClient;

            # OCI images
            container = atticServerImage;
            attic-server-image = atticServerImage;
            attic-gc-image = atticGCImage;

            # Combined tarball for manual deployment
            container-tarball = pkgs.runCommand "attic-server-image.tar.gz" { } ''
              ${atticServerImage.copyToDockerDaemon}/bin/copy-to-docker-daemon | gzip > $out
            '';
          };

          # Checks for CI validation
          checks = {
            # Formatting check
            formatting = treefmtEval.config.build.check self;

            # Nix linting
            statix = pkgs.runCommand "statix-check" { } ''
              ${pkgs.statix}/bin/statix check ${self} && touch $out
            '';

            # Dead code detection
            deadnix = pkgs.runCommand "deadnix-check" { } ''
              ${pkgs.deadnix}/bin/deadnix --fail ${self} && touch $out
            '';

            # Verify attic packages build
            attic-client-check = atticClient;
            attic-server-check = atticServer;

            # Verify container image builds
            container-check = atticServerImage;
          };

          # Formatter
          formatter = treefmtEval.config.build.wrapper;

          # Apps for easy execution
          apps = {
            default = {
              type = "app";
              program = "${atticClient}/bin/attic";
            };
            attic = {
              type = "app";
              program = "${atticClient}/bin/attic";
            };
            atticd = {
              type = "app";
              program = "${atticServer}/bin/atticd";
            };
          };
        }
      ) // {
      # System-independent outputs

      overlays.default = _final: prev: {
        # Add any custom overlays here
        attic-server = attic.packages.${prev.system}.attic-server or attic.packages.${prev.system}.default;
        attic-client = attic.packages.${prev.system}.attic or attic.packages.${prev.system}.attic-client;
      };

      # NixOS/nix-darwin modules (placeholder for future use)
      nixosModules.default = { config, lib, ... }: {
        options.services.attic-cache = {
          enable = lib.mkEnableOption "Attic cache client configuration";

          cacheUrl = lib.mkOption {
            type = lib.types.str;
            default = "https://nix-cache.fuzzy-dev.tinyland.dev/main";
            description = "URL of the Attic cache";
          };

          publicKey = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Public key for the cache (will be populated after deployment)";
          };
        };

        config = lib.mkIf config.services.attic-cache.enable {
          nix.settings = {
            substituters = [ config.services.attic-cache.cacheUrl ];
            trusted-public-keys = lib.optional
              (config.services.attic-cache.publicKey != "")
              config.services.attic-cache.publicKey;
          };
        };
      };
    };

  # Dogfooding: use our own cache once deployed
  # Uncomment after initial deployment and key generation
  nixConfig = {
    extra-substituters = [
      # "https://nix-cache.fuzzy-dev.tinyland.dev/main"
    ];
    extra-trusted-public-keys = [
      # "main:<public-key-to-be-generated>"
    ];
  };
}
