#!/usr/bin/env bash
set -euo pipefail

LABEL="${PRIVATE_MOMENTS_LAUNCHD_LABEL:-com.private-moments.server}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

launchctl bootout "$GUI_DOMAIN" "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"

echo "Uninstalled $LABEL"

