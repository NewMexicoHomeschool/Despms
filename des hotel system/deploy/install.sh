#!/usr/bin/env bash
# DezPMS — self-host install (get the image, then compose up).
#
#   curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh | bash
#
# Or: clone the repo, cd deploy, ./install.sh
#
# Two ways to get the image (Frappe + payments + DezPMS):
#
#   build (default)  build it on this machine via frappe_docker's layered
#                    Containerfile. 20–45 minutes; needs buildx and ~8 GB
#                    RAM+swap (a swap file is added when short). Also the
#                    path for forks / a custom apps.json (DezPMS_APPS_JSON=).
#   pull (opt-in)    DezPMS_PULL=1 (or DezPMS_TAG=…): pull the prebuilt
#                    ghcr.io/DezPMS-pms/DezPMS:stable, resolve `stable` to the
#                    concrete release (e.g. v2.6.16) and pin it, so restarts
#                    never float. Needs registry access: while the package is
#                    private, `docker login ghcr.io` first (a token with
#                    read:packages). A refused pull explains why and falls
#                    back to building.
#
# Asks three things (or reads env): SITE_NAME, ADMIN_EMAIL, ADMIN_PASSWORD.
# Creates the Frappe site, installs payments + DezPMS, enables the scheduler,
# points / at /DezPMS. There is no default password.
#
# Modes:
#   install.sh            install (safe to re-run; reuses DB password + site)
#   install.sh update     backup (bench backup --with-files; abort on failure),
#                         pull the new image (or rebuild), recreate, migrate
#   install.sh build      build the image only (Packer snapshots that need a
#                         custom build); later install/update stay in build mode
#   install.sh pull       pull + pin the image only (Packer / 1-Click snapshots);
#                         later install/update stay in pull mode
#
# Env:
#   DezPMS_PULL    1 = pull the prebuilt image instead of building
#   DezPMS_TAG     tag to pull (implies pull): stable (default), vX.Y.Z, nightly
#   DezPMS_IMAGE   default ghcr.io/DezPMS-pms/DezPMS (pull) / DezPMS (build)
#   DezPMS_BUILD   1 = build locally (wins over DezPMS_PULL / DezPMS_TAG)
#   DezPMS_PULL_FALLBACK  0 = fail instead of building when the pull is refused
#
# The installer copies itself to $INSTALL_DIR/install.sh, so updates are:
#   sudo /opt/DezPMS/install.sh update
set -euo pipefail

# Absolute path of this script (empty when piped via curl | bash); resolved
# now because later steps cd into frappe_docker.
SELF=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
fi

MODE="${1:-install}"
case "$MODE" in
  install|update|build|pull) ;;
  *) echo "usage: install.sh [install|update|build|pull]" >&2; exit 2 ;;
esac

# How a fresh install gets its image when nothing else says: build | pull.
# Flip to `pull` once ghcr.io/DezPMS-pms/DezPMS is public.
DEFAULT_MODE=build

INSTALL_DIR="${INSTALL_DIR:-/opt/DezPMS}"
ENVFILE="$INSTALL_DIR/DezPMS.env"
APPS_JSON="$INSTALL_DIR/apps.json"
# Non-secret record of which image this install runs (mode, image, channel,
# pinned tag). Read on every run so `update` follows what was installed.
IMAGE_STATE="$INSTALL_DIR/image.env"

PUBLIC_IMAGE="ghcr.io/DezPMS-pms/DezPMS"
LOCAL_IMAGE="DezPMS"
LOCAL_TAG="local"

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
yellow() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
die() { red "error: $*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "need '$1' on PATH"; }

# state_get KEY — read one value from image.env (never sourced).
state_get() {
  [ -f "$IMAGE_STATE" ] || return 0
  sed -n "s/^$1=//p" "$IMAGE_STATE" | tail -1
}

# --- image selection: explicit env > recorded image.env > defaults ----------
# DezPMS_TAG on the command line is the *channel* to follow (stable, nightly,
# vX.Y.Z); DezPMS_PINNED is the concrete tag compose actually runs.
REC_MODE="$(state_get DezPMS_MODE)"
# Installs from before pull mode existed have no image.env but a local
# DezPMS:local build (PULL_POLICY=never) — keep building those unless asked.
if [ -z "$REC_MODE" ] && [ -f "$ENVFILE" ] && grep -q '^PULL_POLICY=never' "$ENVFILE"; then
  REC_MODE=build
fi
if [ "$MODE" = build ] || [ "$MODE" = pull ]; then
  DezPMS_MODE="$MODE"
elif [ -n "${DezPMS_BUILD:-}" ]; then
  if [ "$DezPMS_BUILD" = 1 ]; then DezPMS_MODE=build; else DezPMS_MODE=pull; fi
elif [ -n "${DezPMS_PULL:-}" ]; then
  if [ "$DezPMS_PULL" = 1 ]; then DezPMS_MODE=pull; else DezPMS_MODE=build; fi
elif [ -n "${DezPMS_TAG:-}" ]; then
  DezPMS_MODE=pull
else
  DezPMS_MODE="${REC_MODE:-$DEFAULT_MODE}"
fi

if [ "$DezPMS_MODE" = build ]; then
  DezPMS_IMAGE="${DezPMS_IMAGE:-$LOCAL_IMAGE}"
  DezPMS_TAG="${DezPMS_TAG:-$LOCAL_TAG}"
else
  if [ "$REC_MODE" = pull ]; then
    DezPMS_IMAGE="${DezPMS_IMAGE:-$(state_get DezPMS_IMAGE)}"
    DezPMS_TAG="${DezPMS_TAG:-$(state_get DezPMS_CHANNEL)}"
  fi
  DezPMS_IMAGE="${DezPMS_IMAGE:-$PUBLIC_IMAGE}"
  DezPMS_TAG="${DezPMS_TAG:-stable}"
fi
DezPMS_PINNED="${DezPMS_TAG}"

DezPMS_GIT_URL="${DezPMS_GIT_URL:-https://github.com/DezPMS-PMS/DezPMS-pms}"
DezPMS_BRANCH_OVERRIDE="${DezPMS_BRANCH:-}"
DezPMS_BRANCH="${DezPMS_BRANCH:-main}"
DezPMS_APPS_JSON="${DezPMS_APPS_JSON:-}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
FRAPPE_PATH="${FRAPPE_PATH:-https://github.com/frappe/frappe}"
FRAPPE_DOCKER_REPO="${FRAPPE_DOCKER_REPO:-https://github.com/frappe/frappe_docker.git}"
# Pinned so an upstream change can't break every fresh install. Bump
# deliberately after the deploy-smoke CI job passes on the new ref.
FRAPPE_DOCKER_REF="${FRAPPE_DOCKER_REF:-3d0a0e53d8ab03903f6c3f125976a37d7a0f9875}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
# The published image is linux/amd64 (frappe_docker's compose pins that too).
DezPMS_PLATFORM="${DezPMS_PLATFORM:-linux/amd64}"
MIN_PASSWORD_LEN=10
# Build RAM floor (MiB, RAM + swap). Below this we add a swap file.
BUILD_MEM_MB=8000

# When piped (curl | bash), stdin is the script — reopen the terminal for prompts.
if [ "$MODE" = install ] && [ ! -t 0 ] && [ -z "${SITE_NAME:-}" ]; then
  exec < /dev/tty || die "cannot read prompts (run: bash install.sh, or export SITE_NAME ADMIN_EMAIL ADMIN_PASSWORD)"
fi

prompt() {
  local var="$1" label="$2" secret="${3:-}"
  if [ -n "${!var:-}" ]; then
    return 0
  fi
  if [ -n "$secret" ]; then
    read -r -s -p "$label: " value
    echo
  else
    read -r -p "$label: " value
  fi
  export "$var=$value"
}

echo
echo "  DezPMS — open-source hotel PMS"
echo "  https://DezPMSpms.com"
echo
if [ "$DezPMS_MODE" = build ]; then
  echo "  Build mode: the Docker image is built on THIS server"
  echo "  (Frappe + payments + DezPMS). Plan for 20–45 minutes and"
  echo "  40 GB disk. Under 8 GB RAM a swap file is added for the build."
  echo "  (With access to the prebuilt image: DezPMS_PULL=1 — a few minutes.)"
else
  echo "  Pulling the prebuilt image ${DezPMS_IMAGE}:${DezPMS_TAG}"
  echo "  (Frappe + payments + DezPMS). Usually 2–5 minutes."
  echo "  Custom apps / forks: DezPMS_BUILD=1 builds locally instead."
  case "$(uname -m)" in
    aarch64|arm64) yellow "  note: the image is linux/amd64; on this ARM server it runs under emulation." ;;
  esac
fi
echo

# --- Docker -----------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Installing Docker Engine…"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker 2>/dev/null || true
fi
need_cmd docker
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 required (docker compose)"

# --- helpers used by every mode ---------------------------------------------
# layered Containerfile uses RUN --mount=type=secret, which needs BuildKit
# via buildx. Ubuntu's docker.io package ships without it. Build mode only.
ensure_buildx() {
  if ! docker buildx version >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      echo "Installing docker buildx…"
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker-buildx >/dev/null 2>&1 \
        || DEBIAN_FRONTEND=noninteractive apt-get install -y docker-buildx-plugin >/dev/null 2>&1 || true
    fi
    docker buildx version >/dev/null 2>&1 || die "docker buildx is required (apt install docker-buildx-plugin)"
  fi
  export DOCKER_BUILDKIT=1
}

ensure_build_memory() {
  local mem_mb swap_mb need_mb
  mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
  swap_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
  [ "$mem_mb" -gt 0 ] || return 0  # not Linux; let docker decide
  if [ $((mem_mb + swap_mb)) -ge "$BUILD_MEM_MB" ]; then
    return 0
  fi
  need_mb=$((BUILD_MEM_MB - mem_mb - swap_mb))
  [ "$need_mb" -lt 2048 ] && need_mb=2048
  if [ -e /swapfile-DezPMS ]; then
    swapon /swapfile-DezPMS 2>/dev/null || true
    return 0
  fi
  echo "Only ${mem_mb} MB RAM + ${swap_mb} MB swap — adding a ${need_mb} MB swap file for the build…"
  if fallocate -l "${need_mb}M" /swapfile-DezPMS 2>/dev/null \
    || dd if=/dev/zero of=/swapfile-DezPMS bs=1M count="$need_mb" status=none; then
    chmod 600 /swapfile-DezPMS
    mkswap /swapfile-DezPMS >/dev/null
    swapon /swapfile-DezPMS
    grep -q '^/swapfile-DezPMS ' /etc/fstab 2>/dev/null \
      || echo '/swapfile-DezPMS none swap sw 0 0' >> /etc/fstab
  else
    red "warning: could not add swap; the build may run out of memory"
  fi
}

checkout_frappe_docker() {
  mkdir -p "$INSTALL_DIR"
  if [ ! -d "$INSTALL_DIR/frappe_docker/.git" ]; then
    echo "Fetching frappe_docker@${FRAPPE_DOCKER_REF:0:12} → $INSTALL_DIR/frappe_docker"
    git init -q "$INSTALL_DIR/frappe_docker"
    git -C "$INSTALL_DIR/frappe_docker" remote add origin "$FRAPPE_DOCKER_REPO"
  fi
  if [ "$(git -C "$INSTALL_DIR/frappe_docker" rev-parse HEAD 2>/dev/null)" != "$FRAPPE_DOCKER_REF" ]; then
    git -C "$INSTALL_DIR/frappe_docker" fetch -q --depth 1 origin "$FRAPPE_DOCKER_REF"
    git -C "$INSTALL_DIR/frappe_docker" checkout -q --force FETCH_HEAD
  fi
  cd "$INSTALL_DIR/frappe_docker"
  # Prefer Valkey (BSD-3, Linux Foundation) for cache/queue (#392). Keep
  # redis-* service names and redis:// bench URLs — Frappe speaks RESP.
  # Idempotent rewrite of upstream compose.redis.yaml image pins.
  if [ -f overrides/compose.redis.yaml ]; then
    # -i.bak is portable across GNU and BSD sed.
    sed -i.bak 's|image: redis:[^[:space:]]*|image: valkey/valkey:8-alpine|g' \
      overrides/compose.redis.yaml
    rm -f overrides/compose.redis.yaml.bak
  fi
}

write_apps_json() {
  if [ -n "$DezPMS_APPS_JSON" ]; then
    [ -f "$DezPMS_APPS_JSON" ] || die "DezPMS_APPS_JSON=${DezPMS_APPS_JSON} not found"
    if [ "$DezPMS_APPS_JSON" != "$APPS_JSON" ]; then
      cp "$DezPMS_APPS_JSON" "$APPS_JSON"
    fi
    return 0
  fi
  cat > "$APPS_JSON" <<EOF
[
  {"url": "https://github.com/frappe/payments", "branch": "develop"},
  {"url": "${DezPMS_GIT_URL}", "branch": "${DezPMS_BRANCH}"}
]
EOF
}

# CACHE_BUST changes every run, so Docker re-runs `bench init` and fetches
# the current apps. (The apps.json secret alone does not bust the cache.)
build_image() {
  ensure_buildx
  ensure_build_memory
  echo "Building ${DezPMS_IMAGE}:${DezPMS_TAG} from ${APPS_JSON}…"
  echo "  (first build downloads the Frappe toolchain — go stretch)"
  docker build \
    -t "${DezPMS_IMAGE}:${DezPMS_TAG}" \
    -f images/layered/Containerfile \
    --build-arg "FRAPPE_PATH=${FRAPPE_PATH}" \
    --build-arg "FRAPPE_BRANCH=${FRAPPE_BRANCH}" \
    --build-arg "CACHE_BUST=${DezPMS_BRANCH}-$(date +%s)" \
    --secret "id=apps_json,src=${APPS_JSON}" \
    . || die "docker build failed — see output above (disk full? out of memory?)"
  DezPMS_PINNED="$DezPMS_TAG"
}

# DezPMS version baked into an image ("" if unreadable).
image_DezPMS_version() {
  docker run --rm --platform "$DezPMS_PLATFORM" --entrypoint cat "$1" \
    /home/frappe/frappe-bench/apps/DezPMS/DezPMS/__init__.py 2>/dev/null \
    | sed -n 's/^__version__ *= *"\([^"]*\)".*/\1/p' | head -1
}

image_id() { docker image inspect -f '{{.Id}}' "$1" 2>/dev/null || true; }

# pull_image — pull ${DezPMS_IMAGE}:${DezPMS_TAG} and set DezPMS_PINNED to the
# concrete release it is (stable/latest → vX.Y.Z), so compose never floats.
# Returns 1 when the registry refuses (private package, no network, wrong
# CPU architecture); PULL_ERROR holds the message.
PULL_ERROR=""
pull_image() {
  local ref="${DezPMS_IMAGE}:${DezPMS_TAG}" out ver
  echo "Pulling ${ref}…"
  if ! out=$(docker pull --platform "$DezPMS_PLATFORM" "$ref" 2>&1); then
    PULL_ERROR="$out"
    # :stable is published from the first release after it was introduced;
    # before that :latest is the same channel.
    case "$DezPMS_TAG:$out" in
      stable:*"not found"*|stable:*"manifest unknown"*)
        ref="${DezPMS_IMAGE}:latest"
        echo "  no :stable tag yet — trying ${ref}"
        out=$(docker pull --platform "$DezPMS_PLATFORM" "$ref" 2>&1) || { PULL_ERROR="$out"; return 1; }
        ;;
      *) return 1 ;;
    esac
  fi
  printf '%s\n' "$out" | tail -2
  DezPMS_PINNED="$DezPMS_TAG"
  case "$DezPMS_TAG" in
    stable|latest)
      ver=$(image_DezPMS_version "$ref")
      if [ -n "$ver" ] && docker pull -q --platform "$DezPMS_PLATFORM" "${DezPMS_IMAGE}:v${ver}" >/dev/null 2>&1 \
        && [ "$(image_id "${DezPMS_IMAGE}:v${ver}")" = "$(image_id "$ref")" ]; then
        DezPMS_PINNED="v${ver}"
        echo "  ${DezPMS_TAG} is ${DezPMS_PINNED} — pinned."
      else
        yellow "warning: could not resolve ${ref} to a vX.Y.Z tag; running ${DezPMS_TAG} as pulled"
      fi
      ;;
  esac
  return 0
}

explain_pull_failure() {
  red "Could not pull ${DezPMS_IMAGE}:${DezPMS_TAG}:"
  printf '%s\n' "$PULL_ERROR" | tail -3 >&2
  case "$PULL_ERROR" in
    *denied*|*unauthorized*|*UNAUTHORIZED*|*DENIED*)
      yellow "The registry refused the pull — the image package is not public (yet),"
      yellow "or this server is logged in to ghcr.io with a token that cannot read it."
      ;;
    *"no matching manifest"*)
      yellow "The prebuilt image is linux/amd64 only; this server is $(uname -m)."
      ;;
    *)
      yellow "Network problem or unknown tag? Check: docker pull ${DezPMS_IMAGE}:${DezPMS_TAG}"
      ;;
  esac
}

# Switch this run to build mode (pull refused during install).
fall_back_to_build() {
  yellow "Falling back to BUILD mode: building the image on this server (20–45 minutes)."
  DezPMS_MODE=build
  DezPMS_IMAGE="$LOCAL_IMAGE"
  DezPMS_TAG="$LOCAL_TAG"
  DezPMS_PINNED="$LOCAL_TAG"
  write_apps_json
  build_image
}

write_image_state() {
  mkdir -p "$INSTALL_DIR"
  cat > "$IMAGE_STATE" <<EOF
# Generated by DezPMS install.sh — which image this install runs.
# DezPMS_CHANNEL is what \`install.sh update\` follows; DezPMS_PINNED is running.
DezPMS_MODE=${DezPMS_MODE}
DezPMS_IMAGE=${DezPMS_IMAGE}
DezPMS_CHANNEL=${DezPMS_TAG}
DezPMS_PINNED=${DezPMS_PINNED}
EOF
}

# DezPMS.env — compose env (DB password + image), mode 600.
write_envfile() {
  local pull_policy
  # never: a local build must not hit a registry. missing: the pinned tag is
  # pulled by this script; compose restarts never re-pull or float.
  if [ "$DezPMS_MODE" = build ]; then pull_policy=never; else pull_policy=missing; fi
  umask 077
  cat > "$ENVFILE" <<EOF
# Generated by DezPMS install.sh — do not commit.
DB_PASSWORD=${DB_PASSWORD}
CUSTOM_IMAGE=${DezPMS_IMAGE}
CUSTOM_TAG=${DezPMS_PINNED}
PULL_POLICY=${pull_policy}
# compose still interpolates this even with CUSTOM_IMAGE set
ERPNEXT_VERSION=${DezPMS_PINNED}
FRAPPE_SITE_NAME_HEADER=${SITE_NAME}
HTTP_PUBLISH_PORT=${HTTP_PUBLISH_PORT}
EOF
  umask 022
}

compose() {
  docker compose --project-name DezPMS --env-file "$ENVFILE" \
    -f compose.yaml \
    -f overrides/compose.mariadb.yaml \
    -f overrides/compose.redis.yaml \
    -f overrides/compose.noproxy.yaml "$@"
}

wait_for_backend() {
  echo "Waiting for MariaDB and backend…"
  for _ in $(seq 1 60); do
    if compose exec -T backend bench --version >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  die "backend did not become ready — check: docker compose -p DezPMS logs"
}

install_self() {
  # Keep a copy next to the stack so `install.sh update` works later.
  if [ -n "$SELF" ] && [ "$SELF" != "$INSTALL_DIR/install.sh" ]; then
    cp "$SELF" "$INSTALL_DIR/install.sh" && chmod +x "$INSTALL_DIR/install.sh"
  elif [ ! -f "$INSTALL_DIR/install.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh \
      -o "$INSTALL_DIR/install.sh" && chmod +x "$INSTALL_DIR/install.sh" || true
  fi
}

# --- build / pull: image only (Packer / Marketplace snapshots) --------------
if [ "$MODE" = build ]; then
  checkout_frappe_docker
  write_apps_json
  build_image
  write_image_state
  install_self
  green "Built ${DezPMS_IMAGE}:${DezPMS_TAG}. First boot: ${INSTALL_DIR}/install.sh"
  exit 0
fi

if [ "$MODE" = pull ]; then
  checkout_frappe_docker
  if ! pull_image; then
    explain_pull_failure
    die "image not pulled (build instead: ${INSTALL_DIR}/install.sh build)"
  fi
  write_image_state
  install_self
  green "Pulled ${DezPMS_IMAGE}:${DezPMS_PINNED}. First boot: ${INSTALL_DIR}/install.sh"
  exit 0
fi

# --- update: backup, new image, recreate, migrate ---------------------------
if [ "$MODE" = update ]; then
  [ -f "$ENVFILE" ] || die "no ${ENVFILE} — run install first"
  SITE_NAME=$(sed -n 's/^FRAPPE_SITE_NAME_HEADER=//p' "$ENVFILE" | head -1)
  DB_PASSWORD=$(sed -n 's/^DB_PASSWORD=//p' "$ENVFILE" | head -1)
  HTTP_PUBLISH_PORT=$(sed -n 's/^HTTP_PUBLISH_PORT=//p' "$ENVFILE" | head -1)
  HTTP_PUBLISH_PORT="${HTTP_PUBLISH_PORT:-8080}"
  OLD_TAG=$(sed -n 's/^CUSTOM_TAG=//p' "$ENVFILE" | head -1)
  checkout_frappe_docker
  if [ "$DezPMS_MODE" = build ] && [ -z "${DezPMS_BUILD:-}" ]; then
    echo "This install builds its image locally. With ghcr.io access, switch to the prebuilt image:"
    echo "  DezPMS_PULL=1 ${INSTALL_DIR}/install.sh update"
  fi

  # 1. Get the new image first — a failed pull/build leaves the site untouched.
  if [ "$DezPMS_MODE" = build ]; then
    [ -f "$APPS_JSON" ] || die "no ${APPS_JSON} — run install first"
    # DezPMS_BRANCH=… on the command line switches branch/tag; otherwise keep
    # whatever apps.json already records (custom apps.json stays as is).
    if [ -n "${DezPMS_BRANCH_OVERRIDE:-}" ] || [ -n "$DezPMS_APPS_JSON" ]; then
      DezPMS_BRANCH="${DezPMS_BRANCH_OVERRIDE:-$DezPMS_BRANCH}"
      write_apps_json
    else
      DezPMS_BRANCH=$(grep -o '"branch": *"[^"]*"' "$APPS_JSON" | tail -1 | sed 's/.*"\([^"]*\)"$/\1/')
    fi
    # Build under a staging tag so the backup below still runs on the old one.
    FINAL_TAG="$DezPMS_TAG"
    DezPMS_TAG="${FINAL_TAG}-next"
    build_image
    DezPMS_TAG="$FINAL_TAG"
    DezPMS_PINNED="$FINAL_TAG"
  else
    if ! pull_image; then
      explain_pull_failure
      die "update aborted — nothing changed. To build locally instead: DezPMS_BUILD=1 ${INSTALL_DIR}/install.sh update"
    fi
    if [ "$DezPMS_PINNED" = "$OLD_TAG" ] && [ "$DezPMS_PINNED" != nightly ]; then
      echo "Already on ${DezPMS_PINNED} — re-applying (migrate is idempotent)."
    fi
  fi

  # 2. Backup with the running (old) containers. No backup, no update.
  echo "Backing up all sites (bench backup --with-files)…"
  compose up -d >/dev/null 2>&1 || true
  wait_for_backend
  if ! compose exec -T backend bench --site all backup --with-files; then
    die "backup failed — update aborted, the running version (${OLD_TAG}) is untouched"
  fi
  echo "  backups: docker compose -p DezPMS exec backend ls sites/*/private/backups"

  # 3. Switch to the new image, recreate, migrate.
  if [ "$DezPMS_MODE" = build ]; then
    docker tag "${DezPMS_IMAGE}:${DezPMS_TAG}-next" "${DezPMS_IMAGE}:${DezPMS_TAG}"
    docker rmi "${DezPMS_IMAGE}:${DezPMS_TAG}-next" >/dev/null 2>&1 || true
  fi
  write_envfile
  write_image_state
  echo "Restarting the stack on ${DezPMS_IMAGE}:${DezPMS_PINNED}…"
  compose up -d --force-recreate
  wait_for_backend
  echo "Migrating sites…"
  compose exec -T backend bench --site all migrate
  compose exec -T backend bench --site all clear-cache
  install_self
  if [ "$DezPMS_MODE" = build ]; then
    green "DezPMS updated (built from ${APPS_JSON}, DezPMS ${DezPMS_BRANCH})."
  else
    green "DezPMS updated: ${OLD_TAG} → ${DezPMS_PINNED} (${DezPMS_IMAGE}, following ${DezPMS_TAG})."
  fi
  exit 0
fi

# --- Prompts (WordPress install.php shape) ----------------------------------
# Non-interactive (cloud-init / 1-click): export SITE_NAME ADMIN_EMAIL ADMIN_PASSWORD first.
if [ -z "${SITE_NAME:-}" ] || [ -z "${ADMIN_EMAIL:-}" ] || [ -z "${ADMIN_PASSWORD:-}" ]; then
  prompt SITE_NAME "Site domain (e.g. pms.yourhotel.com)"
  prompt ADMIN_EMAIL "Admin email"
  prompt ADMIN_PASSWORD "Admin password (min ${MIN_PASSWORD_LEN} chars)" secret
  prompt ADMIN_PASSWORD_CONFIRM "Confirm admin password" secret
  [ "${ADMIN_PASSWORD}" = "${ADMIN_PASSWORD_CONFIRM}" ] || die "passwords do not match"
fi

[ -n "${SITE_NAME}" ] || die "SITE_NAME is required"
[[ "${SITE_NAME}" == *.* ]] || die "SITE_NAME should look like a domain (pms.yourhotel.com)"
[[ "${ADMIN_EMAIL}" == *@* ]] || die "ADMIN_EMAIL must be an email address"
[ "${#ADMIN_PASSWORD}" -ge "$MIN_PASSWORD_LEN" ] || die "password must be at least ${MIN_PASSWORD_LEN} characters"

# Re-runs must keep the DB password MariaDB was initialised with.
if [ -z "${DB_PASSWORD:-}" ] && [ -f "$ENVFILE" ]; then
  DB_PASSWORD=$(sed -n 's/^DB_PASSWORD=//p' "$ENVFILE" | head -1)
fi
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 32)}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-$ADMIN_EMAIL}"
HTTP_PUBLISH_PORT="${HTTP_PUBLISH_PORT:-8080}"

# --- frappe_docker checkout + image -----------------------------------------
checkout_frappe_docker

if [ "$DezPMS_MODE" = build ]; then
  write_apps_json
  # Build-mode snapshots ship a pre-built image; plain re-runs reuse it too.
  if docker image inspect "${DezPMS_IMAGE}:${DezPMS_TAG}" >/dev/null 2>&1 && [ "$FORCE_REBUILD" != "1" ]; then
    echo "Image ${DezPMS_IMAGE}:${DezPMS_TAG} already present — skipping build."
    echo "  (to pull new DezPMS code later: ${INSTALL_DIR}/install.sh update)"
  else
    build_image
  fi
else
  # Snapshots (`install.sh pull`) and re-runs already have the pinned image;
  # don't move a running install to a newer release behind the admin's back.
  REC_PINNED="$(state_get DezPMS_PINNED)"
  if [ -n "$REC_PINNED" ] && [ "$(state_get DezPMS_CHANNEL)" = "$DezPMS_TAG" ] \
    && [ "$(state_get DezPMS_IMAGE)" = "$DezPMS_IMAGE" ] \
    && docker image inspect "${DezPMS_IMAGE}:${REC_PINNED}" >/dev/null 2>&1; then
    DezPMS_PINNED="$REC_PINNED"
    echo "Image ${DezPMS_IMAGE}:${DezPMS_PINNED} already present — skipping pull."
    echo "  (to move to a newer release later: ${INSTALL_DIR}/install.sh update)"
  elif ! pull_image; then
    explain_pull_failure
    [ "${DezPMS_PULL_FALLBACK:-1}" = 1 ] || die "pull failed and DezPMS_PULL_FALLBACK=0 — not building"
    fall_back_to_build
  fi
fi
write_image_state

write_envfile

echo "Starting the stack with ${DezPMS_IMAGE}:${DezPMS_PINNED}…"
compose up -d
wait_for_backend

# Idempotent: skip new-site only if this site already has a site_config.json
# (sites/ also holds apps.txt, apps.json, assets, common_site_config.json).
if ! compose exec -T backend test -f "sites/${SITE_NAME}/site_config.json"; then
  echo "Creating site ${SITE_NAME} (this takes a few minutes)…"
  compose exec -T backend bench new-site "$SITE_NAME" \
    --mariadb-user-host-login-scope='%' \
    --db-root-password "$DB_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --install-app payments --install-app DezPMS --no-mariadb-socket
else
  echo "Site ${SITE_NAME} already present — skipping new-site."
fi

echo "First-boot wiring (home → /DezPMS, admin email, scheduler)…"
compose exec -T \
  -e "DezPMS_ADMIN_EMAIL=${ADMIN_EMAIL}" \
  -e "DezPMS_SITE_URL=https://${SITE_NAME}" \
  backend bench --site "$SITE_NAME" execute DezPMS.scripts.first_boot.execute

# Never leave the password sitting in the shell history file if we can help it
unset ADMIN_PASSWORD ADMIN_PASSWORD_CONFIRM
# Strip any leftover from a previous interactive shell export
export ADMIN_PASSWORD=""

green ""
green "DezPMS is up (${DezPMS_IMAGE}:${DezPMS_PINNED})."
green "  Sign in:  http://<server-ip>:${HTTP_PUBLISH_PORT}/DezPMS"
green "            (or https://${SITE_NAME} after you point DNS + TLS)"
green "  User:     Administrator  (email ${ADMIN_EMAIL})"
green "  Password: the one you just set — there is no default."
green "  Next:     open /DezPMS/setup and create your property."
green ""
green "TLS tip: put nginx/Caddy in front, or:"
green "  certbot --nginx -d ${SITE_NAME}"
green ""
install_self
green "Stack dir: ${INSTALL_DIR}   env: ${ENVFILE}   image: ${IMAGE_STATE}"
if [ "$DezPMS_MODE" = build ]; then
  green "Update later (backup, rebuild the image, restart, migrate):"
else
  green "Update later (backup, pull the newest ${DezPMS_TAG}, restart, migrate):"
fi
green "  sudo ${INSTALL_DIR}/install.sh update"
