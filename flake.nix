{
  description = "keisi pattern for Go web apps on NixOS: managed static-binary app boxes + a git-push dev/prod workflow.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # ── Reusable NixOS pieces (imported by box configs) ──────────────────
      nixosModules = {
        base = import ./modules/base.nix; # ssh/firewall/deploy-user/gc/sops age
        apps = import ./modules/apps.nix; # the managed app runner (app@ + Caddy)
      };

      # `keisi-nix.lib.mkHost { system; hostName; modules; }` → a nixosSystem.
      lib.mkHost = import ./lib/mkHost.nix { inherit self nixpkgs sops-nix; };

      # The on-box deploy tool, also exposed so you can `nix run` / inspect it.
      packages = forAllSystems (pkgs: {
        keisi-deploy = pkgs.callPackage ./pkgs/keisi-deploy.nix { };
      });

      # Scaffolds: `nix flake init -t github:<owner>/keisi-nix#app|#infra`
      templates = {
        app = {
          path = ./templates/app;
          description = "A keisi Go web app repo: targets.yml + CI/deploy workflows (plain Go, no per-repo Nix).";
        };
        infra = {
          path = ./templates/infra;
          description = "The box fleet: the shared keisi.co dev/staging host + a prod host example.";
        };
      };

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
