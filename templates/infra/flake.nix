{
  description = "keisi-infra — the app boxes (shared keisi.co dev/staging + per-app prod)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    keisi-nix.url = "github:youruser/keisi-nix"; # TODO(you): your keisi-nix repo
    keisi-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, keisi-nix, ... }: {
    nixosConfigurations = {
      # The one shared box every app deploys to on push-to-main.
      keisi = keisi-nix.lib.mkHost {
        system = "x86_64-linux"; # "aarch64-linux" for ARM
        hostName = "keisi";
        modules = [ ./hosts/keisi.nix ];
      };

      # A dedicated prod box, added when an app is promoted. One per app.
      kirkpatrick-prod = keisi-nix.lib.mkHost {
        system = "x86_64-linux";
        hostName = "kirkpatrick-prod";
        modules = [ ./hosts/kirkpatrick-prod.nix ];
      };
    };
  };

  # Deploy a box (rarely — only when its config changes):
  #   nixos-rebuild switch --flake .#keisi --target-host deploy@<ip> --use-remote-sudo
  # App code deploys go through keisi-deploy from each app's CI, not here.
}
