# Quickstart (Docker)

The fastest self-host path: one Docker-capable Linux server, **three
questions**, then the installer gets the DezPMS image (Frappe + payments +
DezPMS) and creates your site. By default it **builds the image on your
VPS**; if you have access to the prebuilt image on `ghcr.io` it can
[pull it instead](#faster-pull-the-prebuilt-image) in a few minutes.

## What you need

- A server or VPS: **2 vCPU · 4 GB RAM · 40 GB disk** minimum (Ubuntu
  22.04/24.04); **4 vCPU · 8 GB** recommended. Under 8 GB the installer adds
  a swap file so the image build doesn't run out of memory - it just builds
  slower.
- Docker Engine ≥ 24 with Compose v2 (the installer can install Docker for you)
- A domain (e.g. `pms.yourhotel.com`) pointed at the server
- **20-45 minutes** for the first image build (a few minutes when
  [pulling the prebuilt image](#faster-pull-the-prebuilt-image))

::: tip Where to get a server
Cheapest path for India / SEA: buy Hostinger with
**[our referral link](https://www.hostinger.com/in?REFERRALCODE=DezPMSpms)**
(or coupon **`DezPMSPMS`**) - you save **20%**, and it helps keep DezPMS afloat.
Full walkthrough: [Hostinger](/self-hosting/hostinger).

Also: [DigitalOcean](/self-hosting/digitalocean), [Linode](/self-hosting/linode),
[AWS](/self-hosting/aws). Prefer managed? [Frappe Cloud](/self-hosting/frappe-cloud).
:::

## One command

```bash
curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh | bash
```

You will be asked for:

| Field | Example |
| --- | --- |
| Site domain | `pms.yourhotel.com` |
| Admin email | `you@yourhotel.com` |
| Admin password | (min 10 characters - **there is no default**) |

The script clones `frappe_docker`, builds a local `DezPMS:local` image
(payments + DezPMS from GitHub), starts MariaDB + Valkey (Redis-compatible
cache/queue) + DezPMS, creates the site, enables the scheduler, and points
`/` at `/DezPMS`.

## Faster: pull the prebuilt image

Every release is also published as a Docker image,
`ghcr.io/DezPMS-pms/DezPMS`. Pulling it skips the 20-45 minute build (no
buildx, no swap file) - usually **2-5 minutes** on a VPS connection:

```bash
curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh | DezPMS_PULL=1 bash
```

The installer pulls `:stable`, works out which release that is (say
`v2.6.20`) and **pins** it, so a restart never moves you to a new version
 -  only `install.sh update` does. Pick a tag with `DezPMS_TAG=v2.6.20`
(or `nightly` for testing).

::: warning Registry access
The image package is not public yet. Until it is, log the server in to
`ghcr.io` first with a GitHub token that has `read:packages`:
`echo "$TOKEN" | docker login ghcr.io -u <github-user> --password-stdin`.
Without access the installer says so and falls back to building.
:::

Forks or extra apps (a custom `apps.json`)? Stay on the build path:
`DezPMS_BUILD=1 DezPMS_APPS_JSON=/path/to/apps.json bash install.sh`.

See [Docker images](/self-hosting/#docker-images) for tags and what is
inside the image.

## Try it on your laptop

To look around before you buy a server, a single compose file runs the
prebuilt image with MariaDB and Valkey and creates a site for you (same
registry access as above):

```bash
curl -fsSLO https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/compose/quickstart.yaml
export DezPMS_ADMIN_PASSWORD='pick-a-password'
export DezPMS_DB_PASSWORD="$(openssl rand -hex 16)"
docker compose -f quickstart.yaml up -d
docker compose -f quickstart.yaml logs -f create-site   # wait for "DezPMS is ready"
```

Open <http://localhost:8080/DezPMS> and sign in as `Administrator` with
`DezPMS_ADMIN_PASSWORD`. Nothing is published beyond `127.0.0.1`.
`docker compose -f quickstart.yaml down -v` deletes it all. This is for
evaluation - use the installer for a real hotel.

## Sign in and set up

Open `http://<server-ip>:8080/DezPMS` (or `https://pms.yourhotel.com` after
DNS + TLS).

| Field | Use |
| --- | --- |
| Username | `Administrator` |
| Email | the admin email you entered |
| Password | the password you set |

Then open **`/DezPMS/setup`** and create your property. Product UI is
`/DezPMS`; Frappe Desk at `/app` is an admin escape hatch (accounting apps,
etc.) - not the hotel.

Forgot the password?

```bash
cd /opt/DezPMS/frappe_docker
docker compose --project-name DezPMS --env-file /opt/DezPMS/DezPMS.env \
  -f compose.yaml -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml -f overrides/compose.noproxy.yaml \
  exec backend bench --site pms.yourhotel.com set-admin-password '<new-password>'
```

## TLS

```bash
apt install -y certbot python3-certbot-nginx
# Put nginx in front of port 8080, then:
certbot --nginx -d pms.yourhotel.com
```

## Updating

```bash
sudo /opt/DezPMS/install.sh update
```

Every update first takes a full backup (`bench backup --with-files`, kept
in `sites/<site>/private/backups`) and **stops if the backup fails**. Then:

- **Build installs** rebuild the image from the branch recorded in
  `/opt/DezPMS/apps.json` (fetching the latest DezPMS code). Pin a release
  with `sudo DezPMS_BRANCH=v2.6.20 /opt/DezPMS/install.sh update`. 10-30
  minutes; the site stays up until the containers are recreated.
- **Pull installs** pull the newest `:stable`, pin the release it resolves
  to, and recreate - a few minutes. Move to a specific release with
  `sudo DezPMS_TAG=v2.6.20 /opt/DezPMS/install.sh update`.

Either way it then runs `bench migrate` on every site.

### Going back (downgrade)

There is **no Downgrade button** in the product UI (System Health only
explains how to upgrade; it never changes the site for you).

To leave a newer tag after trying it, pin the release you want and run
the same update command:

```bash
# Pull install - example: leave a trial of a newer release
sudo DezPMS_TAG=v2.6.19 /opt/DezPMS/install.sh update

# Build install - pin the previous release branch/tag
sudo DezPMS_BRANCH=v2.6.19 /opt/DezPMS/install.sh update
```

Use the exact `vX.Y.Z` you were on before (see
[GitHub Releases](https://github.com/DezPMS-PMS/DezPMS-pms/releases)). Do
**not** use `:nightly` on a live hotel - keep production on `:stable` or a
pinned release.

**Caveats**

- Every update already backs up first (`sites/<site>/private/backups`).
  Keep that archive off-site before you experiment.
- `bench migrate` mostly moves **forward**. An older image may not like
  schema or data written by a newer one. If the site misbehaves after
  pinning an older tag, restore the pre-upgrade backup rather than
  forcing the old code onto a newer database.
- DezPMS-operated **nightly.DezPMSpms.com** is a shared develop channel -
  hotels do not upgrade or downgrade it themselves.

Next: [production checklist](/self-hosting/#after-install-production-checklist) ·
[email setup](/self-hosting/email) · [AI assistant](/ai-and-mcp) ·
[ERPNext & HR (optional)](/self-hosting/erpnext-hr)
