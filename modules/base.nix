{ config, lib, pkgs, ... }:

# Box-wide baseline every keisi host imports. This is the declarative
# replacement for scripts/setup-vps.sh's "apt packages + unattended-upgrades,
# UFW, app user, SSH hardening" half. The app runner lives in apps.nix.

let
  inherit (lib) mkOption mkDefault types;
in
{
  options.keisi = {
    adminKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "SSH public keys allowed to log in as the `deploy` sudoer (from the 1Password SSH agent: `ssh-add -L`).";
    };
    upgradeFlake = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "github:youruser/keisi-infra";
      description = "Flake ref this host auto-upgrades from nightly. Null disables auto-upgrade.";
    };
    caddyEmail = mkOption {
      type = types.str;
      example = "you@example.com";
      description = "ACME/Let's Encrypt contact for this box's certs.";
    };
  };

  config = {
    # ── SSH: key-only, no root, no passwords (mirrors the kit's sshd hardening)
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # ── The deploy sudoer. CI (keisi-deploy) and `nixos-rebuild --target-host`
    #    ssh in as this user and use passwordless sudo.
    users.users.deploy = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = config.keisi.adminKeys;
    };
    security.sudo.wheelNeedsPassword = false;

    # ── Firewall: 22/80/443 only (the UFW rule set, declaratively).
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
    };

    # ── Caddy ACME contact (box-wide, like the old global Caddyfile email).
    services.caddy.email = config.keisi.caddyEmail;

    # ── Nix hygiene + flakes.
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    nix.settings.auto-optimise-store = true;

    # ── Automatic security updates (the unattended-upgrades equivalent).
    system.autoUpgrade = lib.mkIf (config.keisi.upgradeFlake != null) {
      enable = true;
      flake = config.keisi.upgradeFlake;
      flags = [ "--update-input" "nixpkgs" "--no-write-lock-file" ];
      dates = "04:00";
      randomizedDelaySec = "45min";
    };

    # sops-nix derives this host's decryption identity from its SSH host key
    # (ssh-to-age); no key material is committed. See ENV-VARS.md.
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # A couple of quality-of-life tools for the operator on the box.
    environment.systemPackages = with pkgs; [ sqlite litestream curl ];

    system.stateVersion = mkDefault "24.11";
  };
}
