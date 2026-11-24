# DezPMS deploy — self-host

By default the installer builds Frappe + payments + DezPMS **on the hotel's
VPS**. With access to the prebuilt image `ghcr.io/DezPMS-pms/DezPMS` it can
pull it instead (`DezPMS_PULL=1`) — see [Pull mode](#pull-mode). The
package is private for now, so pulling needs `docker login ghcr.io` with a
`read:packages` token.

```bash
curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh | bash
```

You will be asked for:

1. **Site domain** — `pms.yourhotel.com`
2. **Admin email**
3. **Admin password** (min 10 characters; there is no default)

First install typically takes **20–45 minutes** (image build). Minimum
**2 vCPU · 4 GB RAM · 40 GB disk**; under 8 GB the installer adds a swap
file (`/swapfile-DezPMS`) so the build doesn't run out of memory. Then open
`/DezPMS/setup` and create the property.

## Modes

| Command | What it does |
| --- | --- |
| `install.sh` | Install. Safe to re-run: keeps the DB password in `DezPMS.env` and skips `new-site` if a site exists. |
| `/opt/DezPMS/install.sh update` | `bench --site all backup --with-files` first (**aborts if it fails**), then rebuild the image from `apps.json` (fresh `CACHE_BUST`) or pull the newest tag of the recorded channel, recreate containers, `bench --site all migrate`. `DezPMS_BRANCH=vX.Y.Z` (build) / `DezPMS_TAG=vX.Y.Z` (pull) pins a release. |
| `install.sh build` | Build the image only — used by Packer to bake 1-Click snapshots so first boot skips the build. |
| `install.sh pull` | Pull + pin the image only — the snapshot step once the image is public. |

## Pull mode

```bash
echo "$TOKEN" | docker login ghcr.io -u <github-user> --password-stdin   # until the package is public
curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh | DezPMS_PULL=1 bash
```

- Pulls `ghcr.io/DezPMS-pms/DezPMS:stable`, reads the DezPMS version inside
  it, checks `:vX.Y.Z` is the same image, and runs that pinned tag
  (`PULL_POLICY=missing`, so restarts never re-pull). No buildx, no swap.
- `DezPMS_TAG=v2.6.16` pins a release; `DezPMS_TAG=nightly` follows nightly.
- `/opt/DezPMS/image.env` records mode / channel / pinned tag; `update`
  follows the channel (`stable` → the newest release).
- A refused pull (private package, no login, wrong CPU) prints why and
  falls back to building (`DezPMS_PULL_FALLBACK=0` fails instead). During
  `update` it aborts without touching anything.
- Flip the default to pull later: `DEFAULT_MODE=pull` in `install.sh`.

Tags: `stable` (newest release), `vX.Y.Z` (pin in production), `nightly`
(testing), `latest` (alias of `stable`). The image is linux/amd64 and holds
only public code — Frappe, payments, DezPMS — no site data or secrets
(those live in Docker volumes and `DezPMS.env` on your server). Old tags
are pruned weekly by `.github/workflows/ghcr-retention.yml` (keeps the 3
newest releases + `stable`/`latest`/`nightly` and the manifests they
reference).

## Try it locally

[`compose/quickstart.yaml`](compose/quickstart.yaml) runs the prebuilt
image + MariaDB + Valkey (Redis-compatible cache/queue) and creates a
site — `docker compose -f quickstart.yaml up -d`, then
<http://localhost:8080/DezPMS>. It needs `DezPMS_ADMIN_PASSWORD` and
`DezPMS_DB_PASSWORD` in the environment (no default secrets) and, while
the package is private, `docker login ghcr.io`. Evaluation only.

Hit `unauthorized` on GHCR? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) and
the copy-paste reply for GitHub reports.

## What gets built

| Piece | Source |
| --- | --- |
| Base | [frappe_docker](https://github.com/frappe/frappe_docker) layered Containerfile |
| Apps | `frappe/payments` + `DezPMS-PMS/DezPMS-pms` (`main` by default) |
| Local tag | `DezPMS:local` (`PULL_POLICY=never`) |

Overrides:

| Env | Default | Purpose |
| --- | --- | --- |
| `DezPMS_BRANCH` | `main` | Git branch/tag of DezPMS-pms to bake in |
| `DezPMS_GIT_URL` | `https://github.com/DezPMS-PMS/DezPMS-pms` | Fork URL |
| `DezPMS_PULL` | unset | `1` = pull the prebuilt image instead of building |
| `DezPMS_BUILD` | unset | `1` = build (wins over `DezPMS_PULL` / `DezPMS_TAG`) |
| `DezPMS_TAG` | `stable` (pull) / `local` (build) | Tag to pull (setting it implies pull mode) |
| `DezPMS_IMAGE` | `ghcr.io/DezPMS-pms/DezPMS` / `DezPMS` | Image name (pull / build) |
| `DezPMS_APPS_JSON` | unset | Custom `apps.json` for build mode (forks, extra apps) |
| `DezPMS_PULL_FALLBACK` | `1` | `0` = fail instead of building when a pull is refused |
| `FORCE_REBUILD` | `0` | Set `1` to rebuild even if the tag exists |
| `FRAPPE_BRANCH` | `version-16` | Frappe branch for the layered build |
| `FRAPPE_DOCKER_REF` | pinned SHA | frappe_docker commit; bump only after `deploy-smoke` CI passes |

## Layout after install

```
/opt/DezPMS/
  install.sh          # copy of the installer, for `install.sh update`
  DezPMS.env           # compose secrets (DB password, site header, image), mode 600
  image.env           # build|pull, image, channel, pinned tag (not secret)
  apps.json           # apps + branch baked into the local image (build mode)
  frappe_docker/      # upstream compose (MariaDB + Valkey via redis override + noproxy)
```

## One-click clouds

| Cloud | Path |
| --- | --- |
| [DigitalOcean](digitalocean/) | Marketplace 1-Click (Packer + cloud-init) |
| [Linode / Akamai](linode/) | Marketplace One-Click (StackScript) |
| [Hostinger](hostinger/) | Affiliate VPS + one paste of `install.sh` |

The DigitalOcean Packer template bakes the image with `install.sh build`,
so first boot only creates the site. The Linode StackScript still builds on
first boot (20–45 minutes).

## Hyperscalers

Free self-host AMI/VM listings are planned. See [docs](../docs-site/self-hosting/marketplace/hyperscalers.md). Do not put a price on the DezPMS software itself on those listings.

## Published images

CI publishes `ghcr.io/DezPMS-pms/DezPMS:{vX.Y.Z,stable,latest}` on every
release (`release.yml`; `stable`/`latest` move only for the newest
release) and `:nightly` (`nightly.yml`). The package is private for now —
pull mode needs a `docker login ghcr.io`; the default install builds.
