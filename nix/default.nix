# Compatibility wrapper for non-flake Nix users
# Usage: nix-build -A attic-client
#        nix-shell

{ system ? builtins.currentSystem
, # pkgs imported via flake-compat, not used directly
  ...
}:

let
  # Try to use flake-compat if available
  flake = (import
    (
      let lock = builtins.fromJSON (builtins.readFile ../flake.lock); in
      fetchTarball {
        url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev or "main"}.tar.gz";
        sha256 = lock.nodes.flake-compat.locked.narHash or "";
      }
    )
    { src = ./..; }
  ).defaultNix;

in
{
  inherit (flake.packages.${system})
    default
    attic-server
    attic-client
    container
    attic-server-image
    attic-gc-image;

  # For nix-shell compatibility
  shell = flake.devShells.${system}.default;
}
