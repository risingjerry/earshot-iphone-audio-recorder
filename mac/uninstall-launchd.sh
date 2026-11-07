#!/bin/bash
# Remove only the sync job; recordings, configuration, logs and state are preserved.
set -euo pipefail
LABEL=dev.earshot.sync
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f -- "$HOME/Library/LaunchAgents/$LABEL.plist"
printf 'Uninstalled %s\n' "$LABEL"
