#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
SERVER_URL="${PRIVATE_MOMENTS_SERVER_URL:-http://127.0.0.1:3210}"
SIM_NAME="${PRIVATE_MOMENTS_SIM_NAME:-Private Moments iPhone 13 Pro}"
DEVICE_TYPE="${PRIVATE_MOMENTS_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro}"
BUNDLE_ID="com.popcornnnnnn.privatemoments"

cd "$ROOT_DIR"

if ! curl -fsS "$SERVER_URL/api/v1/health" >/dev/null 2>&1; then
  mkdir -p "$ROOT_DIR/.tmp"
  echo "Starting Mac server at $SERVER_URL ..."
  npm run server:dev >"$ROOT_DIR/.tmp/server.log" 2>&1 &
  echo "$!" >"$ROOT_DIR/.tmp/server.pid"

  for _ in {1..30}; do
    if curl -fsS "$SERVER_URL/api/v1/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! curl -fsS "$SERVER_URL/api/v1/health" >/dev/null 2>&1; then
    echo "Server did not become healthy. See $ROOT_DIR/.tmp/server.log" >&2
    exit 1
  fi
fi

cd "$IOS_DIR"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

runtime_id="$(xcrun simctl list runtimes | awk '/^iOS / { print $NF }' | tail -n 1)"

if [[ -z "$runtime_id" ]]; then
  echo "No iOS simulator runtime found. Install one from Xcode Settings > Platforms." >&2
  exit 1
fi

sim_udid="$(
  xcrun simctl list devices available \
    | grep -F "$SIM_NAME" \
    | sed -E 's/.*\(([A-F0-9-]{36})\).*/\1/' \
    | head -n 1
)"
if [[ -z "$sim_udid" ]]; then
  sim_udid="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$runtime_id")"
fi

xcrun simctl boot "$sim_udid" >/dev/null 2>&1 || true
open -a Simulator

xcodebuild \
  -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath "$IOS_DIR/build" \
  build \
  CODE_SIGNING_ALLOWED=NO

app_path="$(find "$IOS_DIR/build/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "*.app" -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "Built app was not found under $IOS_DIR/build/Build/Products/Debug-iphonesimulator" >&2
  exit 1
fi

xcrun simctl install "$sim_udid" "$app_path"
xcrun simctl launch "$sim_udid" "$BUNDLE_ID"

echo
echo "Moments is running in Simulator."
echo "Server: $SERVER_URL"
echo "Password: use PRIVATE_MOMENTS_INITIAL_PASSWORD from server/.env"
