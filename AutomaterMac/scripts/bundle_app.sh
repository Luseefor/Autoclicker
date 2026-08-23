#!/bin/zsh
# Bundle Automater.app from a release build + ad-hoc codesign (+ zip).
set -e
ROOT="${0:A:h:h:h}"            # AutomaterMac/scripts → AutomaterMac → repo
APPDIR="$ROOT/AutomaterMac"
BUILD="$APPDIR/.build/release"
DIST="$ROOT/dist"
APP="$DIST/Automater.app"

swift build -c release --package-path "$APPDIR" 2>&1 | tail -1

rm -rf "$APP"
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
  cp "$APPDIR/assets/Automater.icns" "$APP/Contents/Resources/"
else
  echo "note: no icns yet — run scripts/make_icon.py first"
fi

codesign --force --deep -s - "$APP"
echo "signed: $APP"

cd "$DIST" && rm -f Automater.zip && zip -qry Automater.zip Automater.app
echo "zipped: $DIST/Automater.zip ($(du -h Automater.zip | cut -f1))"
