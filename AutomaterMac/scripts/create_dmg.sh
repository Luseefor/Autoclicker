#!/bin/zsh
# Build a polished drag-to-Applications disk image from dist/Automater.app.
set -euo pipefail

ROOT="${0:A:h:h:h}"
DIST="$ROOT/dist"
APP="$DIST/Automater.app"
OUT="$DIST/Automater.dmg"
STAGE="$(mktemp -d)"
VOLUME="Automater"
trap 'rm -rf "$STAGE"' EXIT

[[ -d "$APP" ]] || { echo "Build the app first: AutomaterMac/scripts/bundle_app.sh" >&2; exit 2; }
rm -f "$OUT"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Automater.app"
ln -s /Applications "$STAGE/Applications"

# A simple native background keeps the DMG self-contained and readable.
swift "$ROOT/AutomaterMac/scripts/make_dmg_background.swift" "$STAGE/.background/background.png"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "created $OUT"
