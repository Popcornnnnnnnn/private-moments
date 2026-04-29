#!/usr/bin/env bash
set -euo pipefail

LABEL="${PRIVATE_MOMENTS_LAUNCHD_LABEL:-com.private-moments.server}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$SERVER_DIR/.." && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
STDOUT_LOG="$HOME/Library/Logs/private-moments.out.log"
STDERR_LOG="$HOME/Library/Logs/private-moments.err.log"
NPM_BIN="$(command -v npm)"
NODE_BIN="$(command -v node)"
LAUNCHD_PATH="$(dirname "$NPM_BIN"):$(dirname "$NODE_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
GUI_DOMAIN="gui/$(id -u)"

if [[ ! -f "$SERVER_DIR/.env" ]]; then
  echo "Missing $SERVER_DIR/.env"
  echo "Create it with: cp server/.env.example server/.env"
  exit 1
fi

escape_xml() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

cd "$REPO_DIR"
npm install
npm run admin:build
npm run server:build

cd "$SERVER_DIR"
npx prisma migrate deploy

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(escape_xml "$LABEL")</string>

  <key>WorkingDirectory</key>
  <string>$(escape_xml "$SERVER_DIR")</string>

  <key>ProgramArguments</key>
  <array>
    <string>$(escape_xml "$NPM_BIN")</string>
    <string>run</string>
    <string>start</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$(escape_xml "$STDOUT_LOG")</string>

  <key>StandardErrorPath</key>
  <string>$(escape_xml "$STDERR_LOG")</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>NODE_ENV</key>
    <string>production</string>
    <key>PATH</key>
    <string>$(escape_xml "$LAUNCHD_PATH")</string>
  </dict>
</dict>
</plist>
PLIST

launchctl bootout "$GUI_DOMAIN" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH"
launchctl enable "$GUI_DOMAIN/$LABEL"
launchctl kickstart -k "$GUI_DOMAIN/$LABEL"

echo "Installed $LABEL"
echo "Admin UI: http://127.0.0.1:3210/admin/"
