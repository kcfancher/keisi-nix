# keisi-nix — managed Go app boxes + a git-push workflow

The reusable half of the deploy story. NixOS defines the **boxes**
declaratively; a tiny deploy tool (`keisi-deploy`) ships **app binaries** onto
them. One shared box serves every dev/staging app at `<app>.keisi.co`;
dedicated boxes serve promoted apps at their own TLD. Adding an app needs **no
box rebuild**.

> **Status:** target-state, **not yet piloted** — no `nix flake check` on a
> real box. Review-grade; `TODO(you)` marks every value only you know. This
> **supersedes the earlier `deploy-rs`/per-project-flake scaffold** — that was
> heavier than the seamless-many-apps workflow we landed on. The invariants it
> kept: one CGO-free static binary, hardened systemd unit, loopback/socket
> behind Caddy, `/healthz`-gated deploy with rollback, Litestream for SQLite.

Should become its **own repo** (`github:<owner>/keisi-nix`) so app/infra repos
can pin it. Lives here only as the authoring home.

## The pieces

| Output | What it is |
|---|---|
| `nixosModules.base` | box baseline: ssh hardening, firewall, `deploy` sudoer, gc, sops age identity |
| `nixosModules.apps` | `services.keisi` — the templated `app@` unit + Caddy routing + `keisi-deploy` |
| `lib.mkHost { system; hostName; modules; }` | a `nixosSystem` = base + apps + sops |
| `packages.<sys>.keisi-deploy` | the on-box deploy tool |
| `templates.app` | `nix flake init -t …#app` — a Go app repo's deploy layer (no per-repo Nix) |
| `templates.infra` | `…#infra` — the box fleet (shared keisi.co + a prod host example) |

## How a deploy works

```
app repo: git push main ─► CI builds CGO-free binary ─► scp to box:/tmp
                                                          └─ ssh: sudo keisi-deploy <app> /tmp/<app>.bin
keisi-deploy on the box:  timestamped release ─► pre-swap sqlite .backup ─► flip `current`
                       symlink ─► restart app@<app> ─► poll /healthz over the socket
                       ─► auto-rollback on failure ─► prune
Caddy:  *.keisi.co ─► reverse_proxy unix//run/apps/{subdomain}/app.sock   (no per-app config)
```

Boxes themselves change rarely; when they do:
`nixos-rebuild switch --flake .#keisi --target-host deploy@<ip> --use-remote-sudo`.

## The on-box contract (what `apps.nix` and `keisi-deploy` agree on)

```
/opt/apps/<app>/current            symlink → live release binary
/var/lib/apps/<app>/<app>.db       SQLite DB (+ backups/)
/run/apps/<app>/app.sock           the socket Caddy proxies to
/etc/apps/<app>.env                optional secrets (EnvironmentFile)
app@<app>.service                  the per-app unit (from one template)
```

Injected env: `APP_ADDR` (the socket), `APP_DB`, `APP_ENV` (`staging`|`prod`),
`APP_TRUSTED_PROXY=true`. Apps listen on `APP_ADDR` (unix when it's a path).

## Shared vs dedicated box

```nix
# shared dev/staging (keisi.co): wildcard cert + subdomain-to-socket routing
services.keisi = { enable = true; env = "staging"; wildcardDomain = "keisi.co"; dnsProvider = "cloudflare"; };

# dedicated prod: a normal auto-TLS vhost per real domain
services.keisi = { enable = true; env = "prod"; domains.kirkpatrick = "kirkpatrick.app"; };
```

Secrets are sops-nix (see `../ENV-VARS.md`); dev apps usually need none
(graceful degradation). Local dev is unchanged: `op run --environment <Dev>`.
Full workflow + promotion: `../GITOPS.md`.
