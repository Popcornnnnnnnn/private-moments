#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: npm run restore:local -- <backup.tgz> --yes

Restores a backup created by npm run backup:local.
Existing local runtime data is moved aside before restore.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARCHIVE="${1:-}"
CONFIRM="${2:-}"

if [[ -z "$ARCHIVE" || "$CONFIRM" != "--yes" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Backup archive not found: $ARCHIVE" >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -d server/data ]]; then
  mv server/data "server/data.before-restore-$STAMP"
fi
if [[ -f server/prisma/dev.db ]]; then
  mv server/prisma/dev.db "server/prisma/dev.db.before-restore-$STAMP"
fi

tar -C server -xzf "$ARCHIVE"

cat <<EOF
Restore complete.

Moved previous data aside with timestamp:
  $STAMP

Run:
  npm run server:prisma:deploy
  npm run server:dev
EOF
