#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi
DEVICE_NAME="${PRIVATE_MOMENTS_DEVICE_NAME:-wwz 的 iphone}"
BUNDLE_ID="com.popcornnnnnn.privatemoments"
TAILSCALE_DNS="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName // "" | rtrimstr(".")' 2>/dev/null || true)"
TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
SERVER_URL_CANDIDATES=()

if [[ -n "${PRIVATE_MOMENTS_DEVICE_SERVER_URL:-}" ]]; then
  SERVER_URL_CANDIDATES+=("$PRIVATE_MOMENTS_DEVICE_SERVER_URL")
else
  if [[ -n "$TAILSCALE_DNS" && "$TAILSCALE_DNS" != "null" ]]; then
    SERVER_URL_CANDIDATES+=("https://$TAILSCALE_DNS")
  fi
  if [[ -n "$TAILSCALE_IP" ]]; then
    SERVER_URL_CANDIDATES+=("http://$TAILSCALE_IP:3210")
  fi
  if [[ -n "$LAN_IP" ]]; then
    SERVER_URL_CANDIDATES+=("http://$LAN_IP:3210")
  fi
fi

cd "$ROOT_DIR"

SERVER_URL=""
for candidate in "${SERVER_URL_CANDIDATES[@]}"; do
  if curl -fsS "$candidate/api/v1/health" >/dev/null 2>&1; then
    SERVER_URL="$candidate"
    break
  fi
done

if [[ -z "$SERVER_URL" ]]; then
  echo "The server is not reachable from any detected device URL." >&2
  printf 'Checked:\n' >&2
  printf '  %s\n' "${SERVER_URL_CANDIDATES[@]}" >&2
  echo "Start/restart it with HOST=0.0.0.0 in server/.env, then retry." >&2
  exit 1
fi

node "$ROOT_DIR/scripts/preflight-ios-device.mjs" --server-url "$SERVER_URL" --device "$DEVICE_NAME"

cd "$IOS_DIR"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

mkdir -p "$ROOT_DIR/.tmp"
build_log="$ROOT_DIR/.tmp/ios-device-build.log"
xcodebuild_overrides=()
if [[ -n "${PRIVATE_MOMENTS_FALLBACK_SERVER_URL:-}" ]]; then
  xcodebuild_overrides+=("PRIVATE_MOMENTS_FALLBACK_SERVER_URL=$PRIVATE_MOMENTS_FALLBACK_SERVER_URL")
fi

if ! xcodebuild \
  -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -destination "generic/platform=iOS" \
  -configuration Debug \
  -derivedDataPath "$IOS_DIR/build-device" \
  -allowProvisioningUpdates \
  build \
  "${xcodebuild_overrides[@]}" 2>&1 | tee "$build_log"; then
  if grep -q "No Account for Team\\|No profiles for" "$build_log"; then
    cat >&2 <<MSG

Signing is not configured for this Mac/Xcode account yet.

Open Xcode and complete:
1. Xcode > Settings > Accounts: add/sign in with your Apple ID.
2. Open ios/PrivateMoments.xcodeproj.
3. Select target PrivateMoments > Signing & Capabilities.
4. Select your Team and keep "Automatically manage signing" enabled.
5. Keep the iPhone unlocked and trusted, then rerun: npm run ios:device

The full build log is at: $build_log
MSG
  fi
  exit 1
fi

app_path="$(find "$IOS_DIR/build-device/Build/Products/Debug-iphoneos" -maxdepth 1 -name "*.app" -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "Built app was not found under $IOS_DIR/build-device/Build/Products/Debug-iphoneos" >&2
  exit 1
fi

install_log="$ROOT_DIR/.tmp/ios-device-install.log"
if ! xcrun devicectl device install app --device "$DEVICE_NAME" "$app_path" --timeout 120 2>&1 | tee "$install_log"; then
  echo "Install failed once; retrying after 3 seconds. Keep the iPhone unlocked and trusted." >&2
  sleep 3
  xcrun devicectl device install app --device "$DEVICE_NAME" "$app_path" --timeout 120
fi

launch_log="$ROOT_DIR/.tmp/ios-device-launch.log"
if ! xcrun devicectl device process launch --device "$DEVICE_NAME" "$BUNDLE_ID" 2>&1 | tee "$launch_log"; then
  if grep -q "profile has not been explicitly trusted\\|invalid code signature" "$launch_log"; then
    cat >&2 <<MSG

The app was installed, but iPhone blocked launch until you trust the developer profile.

On the iPhone:
1. Open Settings > General > VPN & Device Management.
2. Under Developer App, trust the Apple Development profile for this app.
3. Then open "Moments" from the Home Screen.

MSG
  fi
  exit 1
fi

echo
echo "Moments is installed and launched on $DEVICE_NAME."
echo "In app Settings, use:"
echo "Server: $SERVER_URL"
if [[ -n "${PRIVATE_MOMENTS_FALLBACK_SERVER_URL:-}" ]]; then
  echo "Fallback server: $PRIVATE_MOMENTS_FALLBACK_SERVER_URL"
fi
echo "Password: use PRIVATE_MOMENTS_INITIAL_PASSWORD from server/.env"
