#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/ios/Config"
LOCAL_CONFIG="$CONFIG_DIR/Local.xcconfig"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi

mkdir -p "$CONFIG_DIR"

{
  echo "// Generated from .env.local by scripts/write-ios-local-config.sh."
  echo "// This file is git-ignored. Edit .env.local or this file for local signing."
  echo

  write_setting() {
    local key="$1"
    local value="${!key:-}"
    if [[ -n "$value" ]]; then
      printf '%s = %s\n' "$key" "$value"
    fi
  }

  write_setting PRIVATE_MOMENTS_IOS_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_TESTS_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_LIST_TESTS_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_APP_GROUP
  write_setting PRIVATE_MOMENTS_DEVELOPMENT_TEAM
  write_setting PRIVATE_MOMENTS_FALLBACK_SERVER_URL
} >"$LOCAL_CONFIG"
