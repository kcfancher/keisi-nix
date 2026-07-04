{ config, pkgs, ... }:

# The shared dev/staging box. Every app is <app>.keisi.co here, auto-deployed
# on push-to-main. Adding an app needs NO change to this file — the wildcard
# vhost routes any <app>.keisi.co to /run/apps/<app>/app.sock once its unit
# exists (created by keisi-deploy on first deploy).

{
  keisi.caddyEmail = "you@keisi.co"; # TODO(you): ACME contact
  keisi.adminKeys = [
    # TODO(you): your SSH public key(s) — `ssh-add -L`
    # "ssh-ed25519 AAAA... you@laptop"
  ];
  # Nightly auto-upgrade needs the box to fetch this (private) repo — leave off
  # for the pilot; turn on once the box has a read deploy key for keisi-infra.
  keisi.upgradeFlake = null;

  services.keisi = {
    enable = true;
    env = "staging";
    wildcardDomain = "keisi.co";
    dnsProvider = "cloudflare"; # DNS-01 wildcard cert; zone can stay wherever it lives
  };

  # Caddy needs the wildcard cert via DNS-01, which needs (a) the DNS
  # provider's Caddy plugin compiled in and (b) a zone-scoped API token
  # exposed as CADDY_DNS_TOKEN.
  services.caddy.package = pkgs.caddy.withPlugins {
    plugins = [ "github.com/caddy-dns/cloudflare@v0.0.0" ]; # TODO(you): pin a real version
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO(you): nix build prints the right hash
  };
  sops.secrets."caddy-dns-token" = { }; # holds CADDY_DNS_TOKEN=...
  systemd.services.caddy.serviceConfig.EnvironmentFile =
    config.sops.secrets."caddy-dns-token".path;

  sops.defaultSopsFile = ../secrets/keisi.yaml; # TODO(you): sops this file
  system.stateVersion = "24.11";
}
