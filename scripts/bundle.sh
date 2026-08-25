#!/usr/bin/env bash
# Assemble Illusory.app.
#
# This is not packaging polish — it is required for the app to work at all.
# Screen Recording and Accessibility are granted by TCC to a bundle identity, and
# a bare SPM executable has none, so permission prompts never appear and capture
# silently returns nothing. Ad-hoc signing keeps the grant stable across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
swift build -c "$CONFIG" --package-path app
BIN="app/.build/arm64-apple-macosx/$CONFIG/Illusory"

APP="build/Illusory.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Illusory"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Illusory</string>
    <key>CFBundleDisplayName</key>       <string>Illusory</string>
    <key>CFBundleIdentifier</key>        <string>app.illusory.Illusory</string>
    <key>CFBundleExecutable</key>        <string>Illusory</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <!-- Agent app: menu bar only, no dock icon, no window on launch. -->
    <key>LSUIElement</key>               <true/>
    <!-- Tokens come back from illusory.fulmina.re through this scheme. -->
    <key>CFBundleURLTypes</key>
    <array>
      <dict>
        <key>CFBundleURLName</key>       <string>app.illusory.Illusory</string>
        <key>CFBundleURLSchemes</key>    <array><string>illusory</string></array>
      </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key>
    <string>Illusory reads the folder and files you have selected in Finder so it can finish what you started.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null
echo "built $APP"
