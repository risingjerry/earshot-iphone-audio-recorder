#!/bin/sh
# Builds the iPhone app (Release) and installs it on your iPhone. A free Apple ID signs apps for 7 days only, so
# scripts/install-resign-job.sh runs this every 4 hours; it reinstalls when the last install is 3+ days old,
# when the code changed since (a new version lands as soon as the phone is reachable), or when forced.
#   install-phone.sh [--force] [device-udid]      --force also relaunches the app on the phone
# Settings come from config.local.env (copy config.example.env).
set -eu
cd "$(dirname "$0")/.."
[ -f config.local.env ] && . ./config.local.env
FORCE=0; [ "${1:-}" = "--force" ] && { FORCE=1; shift; }
DEVICE="${1:-${EARSHOT_DEVICE:-}}"
: "${EARSHOT_TEAM_ID:?set EARSHOT_TEAM_ID in config.local.env}" "${EARSHOT_BUNDLE_PREFIX:?set EARSHOT_BUNDLE_PREFIX in config.local.env}"
[ -n "$DEVICE" ] || { echo "set EARSHOT_DEVICE in config.local.env or pass a UDID"; exit 2; }
export EARSHOT_TEAM_ID EARSHOT_BUNDLE_PREFIX
STAMP="$HOME/Library/Caches/earshot/installed-$DEVICE"
mkdir -p "$(dirname "$STAMP")"
HEAD=$(git rev-parse HEAD)
if [ $FORCE = 0 ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$HEAD" ] \
   && [ $(( $(date +%s) - $(stat -f %m "$STAMP") )) -lt 259200 ]; then
  exit 0
fi
# An idle phone on the same Wi-Fi shows "disconnected"; one cheap query brings the tunnel up.
xcrun devicectl device info apps --device "$DEVICE" -t 30 >/dev/null 2>&1 || { echo "device $DEVICE not reachable"; exit 0; }
xcodegen generate -q
xcodebuild -project Earshot.xcodeproj -scheme Earshot -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build/ios-dd -allowProvisioningUpdates build -quiet
APP=build/ios-dd/Build/Products/Release-iphoneos/Earshot.app
codesign -v "$APP"                                  # never ship a half-signed bundle
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
echo "$HEAD" > "$STAMP"
echo "$(date '+%F %T') installed on $DEVICE"
# A manual deploy (--force) opens the new version at once; the re-sign job never pulls the app to the front.
[ $FORCE = 1 ] && { xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$EARSHOT_BUNDLE_PREFIX.earshot" >/dev/null \
  && echo "relaunched" || echo "relaunch failed (phone locked?)"; }
exit 0
