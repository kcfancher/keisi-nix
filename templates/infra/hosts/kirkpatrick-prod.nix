{ config, ... }:

# A dedicated prod box for one promoted app. Copy this per promotion.
# Differs from keisi.nix only by: env=prod, a real domain (not wildcard),
# real secrets, and Litestream backups on.

{
  keisi.caddyEmail = "you@kirkpatrick.app"; # TODO(you)
  keisi.adminKeys = [
    # TODO(you): your SSH public key(s)
  ];
  keisi.upgradeFlake = "github:youruser/keisi-infra";

  services.keisi = {
    enable = true;
    env = "prod";
    domains.kirkpatrick = "kirkpatrick.app"; # TODO(you): the app's own TLD
  };

  # Prod secrets → /etc/apps/kirkpatrick.env, which the app@ unit loads as
  # EnvironmentFile. sops decrypts it on the box at activation.
  sops.defaultSopsFile = ../secrets/kirkpatrick-prod.yaml; # TODO(you): sops this
  sops.secrets."kirkpatrick-env" = {
    key = "env";
    path = "/etc/apps/kirkpatrick.env";
    owner = "root";
    group = "apps";
    mode = "0640";
  };

  # Continuous SQLite backup for the prod DB.
  sops.secrets."litestream-env" = { key = "litestream"; };
  services.litestream = {
    enable = true;
    environmentFile = config.sops.secrets."litestream-env".path;
    settings.dbs = [{
      path = "/var/lib/apps/kirkpatrick/kirkpatrick.db";
      replicas = [{ url = "s3://your-bucket/kirkpatrick"; }]; # TODO(you)
    }];
  };

  system.stateVersion = "24.11";
}
