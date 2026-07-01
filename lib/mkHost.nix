# keisi-nix.lib.mkHost — build a NixOS app box wired with the keisi baseline.
#
#   keisi-nix.lib.mkHost {
#     system   = "x86_64-linux";        # "aarch64-linux" for ARM boxes
#     hostName = "keisi";
#     modules  = [ ./hosts/keisi.nix ];  # sets services.keisi + secrets
#   }
#
# Returns a nixosSystem. Deploy the box with plain nixos-rebuild:
#   nixos-rebuild switch --flake .#keisi --target-host deploy@<ip> --use-remote-sudo
# App deploys (the fast path) go through keisi-deploy, not this.

{ self, nixpkgs, sops-nix }:

{ system, hostName, modules ? [ ] }:

nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    self.nixosModules.base
    self.nixosModules.apps
    sops-nix.nixosModules.sops
    { networking.hostName = hostName; }
  ] ++ modules;
}
