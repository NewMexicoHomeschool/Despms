#!/usr/bin/env bash
# Bench-path update with the same hard rule as install.sh update:
#   no backup → no update.
# Usage: ./deploy/update-bench.sh <site> [DezPMS-git-ref]
#   site   e.g. jaref.DezPMSpms.com
#   ref    optional branch/tag for apps/DezPMS (default: current branch pull)
set -euo pipefail

SITE="${1:-}"
REF="${2:-}"
[ -n "$SITE" ] || { echo "usage: $0 <site> [git-ref]" >&2; exit 2; }

die() { echo "error: $*" >&2; exit 1; }

command -v bench >/dev/null || die "bench not on PATH (run from the frappe-bench root)"
[ -d apps/DezPMS ] || die "run from the frappe-bench root (apps/DezPMS missing)"

echo "Backing up ${SITE} (bench backup --with-files)…"
bench --site "$SITE" backup --with-files \
  || die "backup failed — update aborted, site untouched"
echo "  backups: sites/${SITE}/private/backups"

echo "Updating DezPMS…"
if [ -n "$REF" ]; then
  git -C apps/DezPMS fetch --tags origin
  git -C apps/DezPMS checkout "$REF"
  git -C apps/DezPMS pull --ff-only origin "$REF" 2>/dev/null \
    || git -C apps/DezPMS pull --ff-only
else
  git -C apps/DezPMS pull --ff-only
fi

echo "Migrating ${SITE}…"
bench --site "$SITE" migrate
bench build --app DezPMS
bench --site "$SITE" clear-cache
bench restart

echo "Done. DezPMS on ${SITE} updated after a successful backup."
