#!/bin/zsh
# Bundle Automater.app from a release build + ad-hoc codesign (+ zip).
#
# Signing happens in a clean staging dir outside the (possibly iCloud/FileProvider
# synced) repo: system-attached com.apple.provenance attributes make codesign
# refuse to sign in place ("resource fork, Finder information, or similar
# detritus"), and that attribute cannot be removed by xattr.
set -e -o pipefail
ROOT="${0:A:h:h:h}"            # AutomaterMac/scripts → AutomaterMac → repo
APPDIR="$ROOT/AutomaterMac"
BUILD="$APPDIR/.build/release"
DIST="$ROOT/dist"

swift build -c release --package-path "$APPDIR" 2>&1 | tail -1

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Automater.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Automater</string>
  <key>CFBundleDisplayName</key><string>Automater</string>
  <key>CFBundleIdentifier</key><string>com.luseefor.automater</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleExecutable</key><string>Automater</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>Automater</string>
  <key>NSAccessibilityUsageDescription</key>
    <string>Automater clicks and types into other apps on your behalf.</string>
</dict></plist>
PLIST

cp "$BUILD/automater-app" "$APP/Contents/MacOS/Automater"

if [ -f "$APPDIR/assets/Automater.icns" ]; then
  cp -X "$APPDIR/assets/Automater.icns" "$APP/Contents/Resources/"
else
  echo "note: no icns yet — run: swift scripts/make_icon.swift && iconutil -c icns assets/Automater.iconset -o assets/Automater.icns"
fi

# Strip any attributes that could trip the detritus check.
xattr -cr "$APP" 2>/dev/null || true
find "$APP" -name '._*' -delete 2>/dev/null || true

# Sign with a stable identity when one exists (keeps the TCC Accessibility
# grant valid across rebuilds); ad-hoc otherwise (grant resets each build).
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/1 valid identities/{next} /"(.+)"/{print $2; exit}')
codesign --force -s "${IDENTITY:--}" "$APP"
codesign -v "$APP"
echo "signed: $APP (identity: ${IDENTITY:-ad-hoc})"

# Deliver the signed bundle into dist/ (signature survives the copy).
mkdir -p "$DIST"
rm -rf "$DIST/Automater.app"
cp -R "$APP" "$DIST/Automater.app"
codesign -v "$DIST/Automater.app"

cd "$DIST" && rm -f Automater.zip && zip -qry Automater.zip Automater.app
echo "zipped: $DIST/Automater.zip ($(du -h Automater.zip | cut -f1))"
