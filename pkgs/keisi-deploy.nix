{ writeShellApplication, sqlite, curl, coreutils, systemd }:

# Wraps keisi-deploy.sh with its runtime deps on PATH. Installed into the box's
# system packages by modules/apps.nix; the `deploy` user runs it via sudo.
writeShellApplication {
  name = "keisi-deploy";
  runtimeInputs = [ sqlite curl coreutils systemd ];
  text = builtins.readFile ./keisi-deploy.sh;
}
