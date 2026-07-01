# Deploy layer for a keisi app

Dropped in by `nix flake init -t github:<owner>/keisi-nix#app` (or copied). Your
repo stays **plain Go** — no per-repo Nix. The box is what's declarative.

## What's here

| File | Purpose |
|---|---|
| `deploy/targets.yml` | where this app deploys (dev = keisi.co, prod = own box) |
| `.github/workflows/ci.yml` | PR/main gate: templ-diff, vet, test, build |
| `.github/workflows/deploy.yml` | main → dev, tag `v*` → prod (approval-gated), via `keisi-deploy` |

## The one app-code requirement: listen on `APP_ADDR`, unix or TCP

The box injects `APP_ADDR` as a **socket path** (`/run/apps/<app>/app.sock`).
Your server must listen on it — one branch in `main`:

```go
addr := os.Getenv("APP_ADDR") // "/run/apps/foo/app.sock" in prod, ":8080" locally
network := "tcp"
if strings.HasPrefix(addr, "/") {
    network = "unix"
    _ = os.Remove(addr) // clear a stale socket from an unclean stop
}
ln, err := net.Listen(network, addr)
// ... srv.Serve(ln)
```

The runner also sets `APP_DB`, `APP_ENV` (`staging`|`prod`), `APP_TRUSTED_PROXY=true`.
(These are the generic successors to the old `<P>_*` per-app prefixes — see
STACK.md.) Secrets, if any, come from `/etc/apps/<app>.env` on the box, not this repo.

## One-time setup

- **Org/owner Actions secret `DEPLOY_SSH_KEY`** — private key whose public half is
  in the boxes' `deploy` user. Set once at the org level and every app repo
  inherits it → new repos need zero secret setup.
- **Environments** (repo Settings → Environments): create `staging` (no gate) and
  `production` (add yourself as a required reviewer — the prod approval gate).
- Fill in `deploy/targets.yml` (`app`, the `dev.ssh`/`dev.url`).

## Daily loop

- Merge to `main` → live at `<app>.keisi.co` in ~a minute.
- Tag `vX.Y.Z` and push → approve → live on the prod box. (Only once `prod:` is
  uncommented in `targets.yml` and the box exists — see the kit's GITOPS.md.)
