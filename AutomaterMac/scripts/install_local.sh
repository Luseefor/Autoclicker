#!/bin/zsh
# Replace the local Automater install without leaving an older instance open.
set -euo pipefail

ROOT="${0:A:h:h:h}"
APP="$ROOT/dist/Automater.app"
DEST="/Applications/Automater.app"
BUNDLE_ID="com.luseefor.automater"

[[ -d "$APP" ]] || { echo "Build first: AutomaterMac/scripts/bundle_app.sh" >&2; exit 2; }

# Request a graceful quit so the active instance can save and release its
# bundle before replacement. Refuse to continue rather than duplicate it.
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
for _ in {1..30}; do
  if ! pgrep -f "$DEST/Contents/MacOS/Automater" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if pgrep -f "$DEST/Contents/MacOS/Automater" >/dev/null 2>&1; then
  echo "Automater is still running; close it, then run this installer again." >&2
  exit 1
fi

if [[ -d "$DEST" ]]; then
  mv "$DEST" "$HOME/.Trash/Automater-previous-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$APP" "$DEST"
xattr -cr "$DEST"
codesign --verify --deep --strict "$DEST"
open -a "$DEST"
echo "installed and opened: $DEST"
