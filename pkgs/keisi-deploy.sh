#!/usr/bin/env bash
# keisi-deploy <app> <new-binary> — receive a built static binary and make it live.
#
# Runs as root on a keisi app box (invoked over ssh: `sudo keisi-deploy <app> /tmp/<app>.bin`).
# The on-box contract (shared by the NixOS `app@` unit and Caddy):
#   /opt/apps/<app>/releases/<ts>/<app>   timestamped releases
#   /opt/apps/<app>/current               symlink → the live release
#   /var/lib/apps/<app>/<app>.db          SQLite DB (+ backups/)
#   /run/apps/<app>/app.sock              the unix socket Caddy proxies to
#   /etc/apps/<app>.env                   optional secrets (EnvironmentFile)
#   systemd unit: app@<app>.service       templated, one per app
#
# Mirrors the legacy deploy.sh guarantees: pre-swap online backup, atomic
# symlink flip, health-gate over the socket, automatic rollback, prune.
set -euo pipefail

app="${1:?usage: keisi-deploy <app> <new-binary>}"
src="${2:?usage: keisi-deploy <app> <new-binary>}"
keep="${KEEP_RELEASES:-5}"

base="/opt/apps/$app"
data="/var/lib/apps/$app"
sock="/run/apps/$app/app.sock"

[ -f "$src" ] || { echo "keisi-deploy: no binary at $src" >&2; exit 1; }

ts="$(date +%Y%m%d-%H%M%S)"
rel="$base/releases/$ts"
install -d "$rel"
install -m0755 "$src" "$rel/$app"
rm -f "$src" || true

# Pre-swap snapshot via the online backup API — NEVER cp a live SQLite file.
if [ -f "$data/$app.db" ]; then
  install -d -o apps -g apps "$data/backups"
  sqlite3 "$data/$app.db" ".backup '$data/backups/$app-$ts.db'" || true
  # shellcheck disable=SC2012
  ls -1t "$data/backups"/*.db 2>/dev/null | tail -n +"$((keep + 1))" | xargs -r rm -f
fi

prev="$(readlink "$base/current" 2>/dev/null || true)"
ln -sfn "$rel/$app" "$base/current"

rollback() {
  echo "keisi-deploy: $1 — rolling back" >&2
  if [ -n "$prev" ]; then
    ln -sfn "$prev" "$base/current"
    systemctl restart "app@$app" || true
  fi
  exit 1
}

systemctl enable "app@$app" >/dev/null 2>&1 || true
# The unit's ExecStartPost already health-gates; a failed start returns non-zero.
systemctl restart "app@$app" || rollback "restart/health failed"

# Belt-and-suspenders: confirm /healthz over the socket ourselves.
ok=""
for _ in $(seq 1 20); do
  if curl -sf --unix-socket "$sock" http://localhost/healthz >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
[ -n "$ok" ] || rollback "healthz never came up"

# Prune old releases.
# shellcheck disable=SC2012
ls -1dt "$base/releases"/*/ 2>/dev/null | tail -n +"$((keep + 1))" | xargs -r rm -rf

echo "keisi-deploy: $app live @ $ts"
