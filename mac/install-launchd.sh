#!/bin/bash
# Install only when explicitly invoked; keep all paths XML-safe via plistlib.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PYTHON="$(command -v python3)"
LABEL=dev.earshot.sync
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG="$("$PYTHON" "$ROOT/mac/earshot.py" config)"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
# Migrate the previous reverse-domain label, reading its owner from the old plist.
for old in "$HOME"/Library/LaunchAgents/com.*.earshot-sync.plist; do
    [ -f "$old" ] || continue
    old_label="$("$PYTHON" - "$old" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    print(plistlib.load(handle)["Label"])
PY
)"
    launchctl bootout "gui/$(id -u)/$old_label" 2>/dev/null || true
    rm -- "$old"
done
"$PYTHON" - "$ROOT" "$PYTHON" "$PLIST" "$CONFIG" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import sys

root, python, destination, raw_config = sys.argv[1:]
config = json.loads(raw_config)
log = str(Path.home() / "Library/Logs/earshot-sync.log")
icloud = Path(config["icloud_dir"])
icloud.mkdir(parents=True, exist_ok=True)
# Freeze the same overrides for launchd, whose environment differs from this shell.
environment = {"PATH": os.environ["PATH"], "EARSHOT_CONFIG": config["config_path"]}
for name in ("EARSHOT_DEVICE", "EARSHOT_APP_GROUP", "EARSHOT_ICLOUD_DIR", "EARSHOT_OUTPUT_DIR"):
    if name in os.environ:
        environment[name] = os.environ[name]
job = {
    "Label": "dev.earshot.sync",
    "ProgramArguments": [python, str(Path(root) / "mac/earshot.py"), "sync"],
    "StartInterval": 600,
    "WatchPaths": [str(icloud)],
    "RunAtLoad": True,
    "Nice": 10,
    "EnvironmentVariables": environment,
    "StandardOutPath": log,
    "StandardErrorPath": log,
}
with open(destination, "wb") as handle:
    plistlib.dump(job, handle)
PY
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf 'Installed %s: %s\n' "$LABEL" "$PLIST"
