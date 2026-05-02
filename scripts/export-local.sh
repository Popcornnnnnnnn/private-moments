#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required for export." >&2
  exit 1
fi

DB_PATH="${PRIVATE_MOMENTS_DATABASE_PATH:-}"
if [[ -z "$DB_PATH" ]]; then
  if [[ -f server/data/app.sqlite ]]; then
    DB_PATH="server/data/app.sqlite"
  elif [[ -f server/prisma/dev.db ]]; then
    DB_PATH="server/prisma/dev.db"
  else
    echo "No local database found. Set PRIVATE_MOMENTS_DATABASE_PATH to export another SQLite file." >&2
    exit 1
  fi
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EXPORT_ROOT="${PRIVATE_MOMENTS_EXPORT_DIR:-$ROOT_DIR/exports}"
EXPORT_DIR="$EXPORT_ROOT/private-moments-export-$STAMP"
ARCHIVE="$EXPORT_DIR.tgz"

mkdir -p "$EXPORT_DIR"

cat >"$EXPORT_DIR/manifest.json" <<EOF
{
  "app": "Private Moments",
  "createdAt": "$STAMP",
  "databasePath": "$DB_PATH",
  "includesMediaFiles": false,
  "note": "This export contains SQLite metadata as JSON. Use backup:local for full media/database recovery."
}
EOF

export_table() {
  local table="$1"
  local output="$2"
  if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -qx "$table"; then
    sqlite3 -json "$DB_PATH" "SELECT * FROM $table;" >"$EXPORT_DIR/$output"
  else
    printf '[]\n' >"$EXPORT_DIR/$output"
  fi
}

export_table posts posts.json
export_table comments comments.json
export_table media media.json
export_table ai_summaries ai_summaries.json

tar -C "$EXPORT_ROOT" -czf "$ARCHIVE" "$(basename "$EXPORT_DIR")"

cat <<EOF
Export created:
  $ARCHIVE

This is a metadata export for inspection or migration planning. It does not include media files.
EOF
