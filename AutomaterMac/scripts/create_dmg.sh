#!/bin/zsh
# Build an automation-themed drag-to-Applications DMG.
set -euo pipefail

ROOT="${0:A:h:h:h}"
DIST="$ROOT/dist"
APP="$DIST/Automater.app"
OUT="$DIST/Automater.dmg"
RW="$DIST/Automater-rw.dmg"
STAGE="$(mktemp -d)"
VOLUME="Automater"
trap 'rm -rf "$STAGE"' EXIT

[[ -d "$APP" ]] || { echo "Build the app first: AutomaterMac/scripts/bundle_app.sh" >&2; exit 2; }
rm -f "$OUT" "$RW"
mkdir -p "$STAGE/.background"

swift "$ROOT/AutomaterMac/scripts/make_dmg_background.swift" "$STAGE/.background/background.png"
hdiutil create -size 40m -fs HFS+ -volname "$VOLUME" -format UDRW "$RW" >/dev/null
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/\/Volumes\// {print $3; exit}')"
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE"' EXIT
cp -R "$APP" "$MOUNT/Automater.app"
ln -s /Applications "$MOUNT/Applications"
mkdir -p "$MOUNT/.background"
cp "$STAGE/.background/background.png" "$MOUNT/.background/background.png"
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 780, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Automater.app" to {190, 215}
    set position of item "Applications" to {490, 215}
    close
    open
    update without registering applications
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -o "$OUT" >/dev/null
rm -f "$RW"
echo "created $OUT"
