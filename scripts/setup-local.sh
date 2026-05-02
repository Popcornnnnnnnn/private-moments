#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: npm run setup:local -- [options]

Prepare a local Private Moments development install.

Options:
  --with-ai       Create server/.venv and install local mlx-whisper support.
  --with-ios      Generate the iOS Xcode project with xcodegen.
  --skip-install  Skip npm install.
  --skip-build    Skip admin/server build checks.
  -h, --help      Show this help text.
EOF
}

log() {
  printf '\033[1;32m[setup]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m[setup]\033[0m %s\n' "$1"
}

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[setup] Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

resolve_sqlite_path() {
  local database_url
  database_url="$(grep -E '^DATABASE_URL=' server/.env 2>/dev/null | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')"
  if [[ -z "$database_url" ]]; then
    printf '%s\n' "$ROOT_DIR/server/data/app.sqlite"
    return
  fi

  if [[ "$database_url" != file:* ]]; then
    printf '[setup] DATABASE_URL is not a SQLite file URL: %s\n' "$database_url" >&2
    exit 1
  fi

  local sqlite_path="${database_url#file:}"
  if [[ "$sqlite_path" = /* ]]; then
    printf '%s\n' "$sqlite_path"
  else
    printf '%s\n' "$ROOT_DIR/server/prisma/$sqlite_path"
  fi
}

sqlite_has_schema() {
  local db_path="$1"
  [[ -f "$db_path" ]] && [[ "$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users';" 2>/dev/null || printf '0')" != "0" ]]
}

apply_sqlite_migrations_fallback() {
  need_command sqlite3

  local db_path
  db_path="$(resolve_sqlite_path)"
  mkdir -p "$(dirname "$db_path")"

  if sqlite_has_schema "$db_path"; then
    warn "Prisma migrate deploy failed, but the SQLite schema already exists. Leaving it unchanged."
    return
  fi

  warn "Prisma migrate deploy failed. Applying SQLite migrations directly as a first-run fallback."
  for migration in server/prisma/migrations/*/migration.sql; do
    log "Applying $(basename "$(dirname "$migration")")"
    sqlite3 "$db_path" < "$migration"
  done
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

WITH_AI=0
WITH_IOS=0
SKIP_INSTALL=0
SKIP_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --with-ai)
      WITH_AI=1
      ;;
    --with-ios)
      WITH_IOS=1
      ;;
    --skip-install)
      SKIP_INSTALL=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[setup] Unknown option: %s\n\n' "$arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

need_command node
need_command npm

if [[ ! -f server/.env ]]; then
  cp server/.env.example server/.env
  log "Created server/.env from server/.env.example"
else
  log "Keeping existing server/.env"
fi

if grep -q '^PRIVATE_MOMENTS_INITIAL_PASSWORD=change-me-before-use$' server/.env; then
  if [[ -t 0 ]]; then
    printf '[setup] Set an initial admin password now? Leave blank to keep placeholder: '
    IFS= read -r -s INITIAL_PASSWORD
    printf '\n'
    if [[ -n "$INITIAL_PASSWORD" ]]; then
      ESCAPED_PASSWORD="$(printf '%s' "$INITIAL_PASSWORD" | sed -e 's/[\/&]/\\&/g')"
      sed -i.bak "s/^PRIVATE_MOMENTS_INITIAL_PASSWORD=.*/PRIVATE_MOMENTS_INITIAL_PASSWORD=${ESCAPED_PASSWORD}/" server/.env
      rm -f server/.env.bak
      log "Updated PRIVATE_MOMENTS_INITIAL_PASSWORD in server/.env"
    else
      warn "server/.env still uses the placeholder password. Edit it before real use."
    fi
  else
    warn "server/.env still uses the placeholder password. Edit it before real use."
  fi
fi

mkdir -p server/data

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  log "Installing npm dependencies"
  npm install
else
  warn "Skipping npm install"
fi

log "Preparing Prisma client and local database"
npm run server:prisma:generate
npm run server:prisma:deploy || apply_sqlite_migrations_fallback

if [[ "$WITH_AI" -eq 1 ]]; then
  need_command python3
  if [[ ! -x server/.venv/bin/python ]]; then
    log "Creating server/.venv"
    python3 -m venv server/.venv
  else
    log "Keeping existing server/.venv"
  fi

  log "Installing local AI transcription dependency: mlx-whisper"
  server/.venv/bin/python -m pip install --upgrade pip
  server/.venv/bin/python -m pip install mlx-whisper
else
  warn "Skipping local AI transcription setup. Run with --with-ai when needed."
fi

if [[ "$WITH_IOS" -eq 1 ]]; then
  need_command xcodegen
  log "Generating iOS Xcode project"
  (cd ios && xcodegen generate)
else
  warn "Skipping iOS project generation. Run with --with-ios when needed."
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  log "Building admin and server"
  npm run admin:build
  npm run server:build
else
  warn "Skipping build checks"
fi

cat <<'EOF'

Setup complete.

Next steps:
  1. Check server/.env and replace any placeholder password.
  2. Start the Mac server:
       npm run server:dev
  3. Open the Admin UI:
       http://127.0.0.1:3210/admin/
  4. Install or run the iOS app when needed:
       PRIVATE_MOMENTS_DEVICE_NAME="Your iPhone" npm run ios:device
       npm run ios:simulator
EOF
