#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

npm run verify:server
npm run verify:ios:generic
npm run verify:uat-gates
git diff --check

if curl -fsS "http://127.0.0.1:3210/api/v1/health" >/dev/null 2>&1; then
  curl -fsS "http://127.0.0.1:3210/api/v1/health"
  echo
else
  echo "Live server health skipped: http://127.0.0.1:3210 is not reachable."
fi
