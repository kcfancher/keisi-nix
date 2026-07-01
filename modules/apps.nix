{ config, lib, pkgs, ... }:

# services.keisi — the managed static-binary app runner.
#
# One templated systemd unit (`app@<name>`) runs any app the deploy tool drops
# in; Caddy routes to each app's unix socket. Adding an app needs NO rebuild of
# this box — it just deploys a binary (keisi-deploy) and, on a shared box, gets a
# subdomain automatically via the wildcard vhost.
#
#   shared dev/staging box:  services.keisi = { env = "staging"; wildcardDomain = "keisi.co"; dnsProvider = "digitalocean"; };
#   dedicated prod box:      services.keisi = { env = "prod"; domains.kirkpatrick = "kirkpatrick.app"; };

let
  inherit (lib) mkOption mkEnableOption types mkIf mkMerge mapAttrs' nameValuePair optionalAttrs optionalString;
  cfg = config.services.keisi;
  keisi-deploy = pkgs.callPackage ../pkgs/keisi-deploy.nix { };
in
{
  options.services.keisi = {
    enable = mkEnableOption "the keisi managed app runner";

    env = mkOption {
      type = types.enum [ "staging" "prod" ];
      default = "staging";
      description = "APP_ENV injected into every app on this box.";
    };

    wildcardDomain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "keisi.co";
      description = ''
        Shared box: serve `*.<domain>` and route `<app>.<domain>` → that app's
        socket, so a newly-deployed app is instantly reachable with no rebuild.
        Requires a DNS-01 wildcard cert (see dnsProvider).
      '';
    };

    dnsProvider = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "cloudflare";
      description = "Caddy DNS plugin name for the wildcard cert (DNS-01). Needed when wildcardDomain is set. Also set the Caddy package with that plugin + a CADDY_DNS_TOKEN env (see the host examples).";
    };

    noindex = mkOption {
      type = types.bool;
      default = true;
      description = "Add X-Robots-Tag noindex on the wildcard (dev) vhost so throwaway apps aren't indexed.";
    };

    domains = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { kirkpatrick = "kirkpatrick.app"; };
      description = "Dedicated/prod box: map <app> → its real FQDN. Each gets a normal auto-TLS vhost to that app's socket.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # ── One shared, sandboxed runtime user for all app instances ─────────
      # (On a shared dev box this trades per-app isolation for simplicity; a
      # prod box runs a single app, so `apps` effectively IS that app's user.)
      users.users.apps = { isSystemUser = true; group = "apps"; };
      users.groups.apps = { };
      users.users.caddy.extraGroups = [ "apps" ]; # so Caddy can reach the sockets

      systemd.tmpfiles.rules = [
        "d /opt/apps     0755 root root -"
        "d /var/lib/apps 0750 apps apps -"
        "d /etc/apps     0750 root apps -"
      ];

      # `keisi-deploy` on PATH; deploy user runs it via (passwordless) sudo.
      environment.systemPackages = [ keisi-deploy pkgs.sqlite ];

      # ── The templated per-app unit (enabled per instance by keisi-deploy) ───
      systemd.services."app@" = {
        description = "keisi app %i";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "/opt/apps/%i/current";
          # Blocks "started" until the socket answers /healthz → a broken
          # binary fails to activate and keisi-deploy rolls back.
          ExecStartPost = "${pkgs.curl}/bin/curl -sf --retry 20 --retry-delay 1 --retry-connrefused --unix-socket /run/apps/%i/app.sock http://localhost/healthz";
          User = "apps";
          Group = "apps";
          UMask = "0007"; # socket is group-accessible so Caddy can connect
          EnvironmentFile = "-/etc/apps/%i.env"; # optional secrets
          Environment = [
            "APP_ADDR=/run/apps/%i/app.sock"
            "APP_DB=/var/lib/apps/%i/%i.db"
            "APP_ENV=${cfg.env}"
            "APP_TRUSTED_PROXY=true"
          ];
          RuntimeDirectory = "apps/%i"; # /run/apps/<app>/
          RuntimeDirectoryMode = "0750";
          StateDirectory = "apps/%i"; # /var/lib/apps/<app>/
          StateDirectoryMode = "0750";

          # hardened profile (free for CGO-free static binaries)
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ "/var/lib/apps" ];
          CapabilityBoundingSet = "";
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          SystemCallFilter = [ "@system-service" ];
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          Restart = "always";
          RestartSec = 2;
        };
      };
    }

    # ── Shared box: one wildcard vhost routes every subdomain by socket ────
    (mkIf (cfg.wildcardDomain != null) {
      assertions = [{
        assertion = cfg.dnsProvider != null;
        message = "services.keisi.wildcardDomain requires dnsProvider (Caddy DNS-01 wildcard cert).";
      }];
      services.caddy = {
        enable = true;
        virtualHosts."*.${cfg.wildcardDomain}".extraConfig = ''
          tls {
            dns ${cfg.dnsProvider} {env.CADDY_DNS_TOKEN}
          }
          ${optionalString cfg.noindex ''header X-Robots-Tag "noindex, nofollow"''}
          reverse_proxy unix//run/apps/{http.request.host.labels.2}/app.sock
        '';
      };
    })

    # ── Dedicated/prod box: a normal auto-TLS vhost per real domain ────────
    (mkIf (cfg.domains != { }) {
      services.caddy = {
        enable = true;
        virtualHosts = mapAttrs' (app: domain:
          nameValuePair domain {
            extraConfig = "reverse_proxy unix//run/apps/${app}/app.sock";
          }
        ) cfg.domains;
      };
    })
  ]);
}
