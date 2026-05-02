#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BACKUP_DIR="${PRIVATE_MOMENTS_BACKUP_DIR:-$ROOT_DIR/backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="$BACKUP_DIR/private-moments-backup-$STAMP.tgz"

mkdir -p "$BACKUP_DIR"

INCLUDES=()
if [[ -d server/data ]]; then
  INCLUDES+=("data")
fi
if [[ -f server/prisma/dev.db ]]; then
  INCLUDES+=("prisma/dev.db")
fi

if [[ "${#INCLUDES[@]}" -eq 0 ]]; then
  echo "No local runtime data found under server/data or server/prisma/dev.db." >&2
  exit 1
fi

tar -C server -czf "$ARCHIVE" "${INCLUDES[@]}"

cat <<EOF
Backup created:
  $ARCHIVE

This archive contains local runtime data only. It does not include server/.env.
EOF
