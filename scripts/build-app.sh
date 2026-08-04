#!/usr/bin/env bash
# Package the SwiftUI menu-bar target into a runnable Kestrel.app accessory bundle.
#
# This is the Phase 7 packaging step. The result is ad-hoc signed so it runs locally;
# Developer ID signing + notarization for distribution is documented in docs/RELEASE.md.
set -euo pipefail

VERSION="0.1.1"           # keep in sync with Sources/KestrelCore/Version.swift
BUNDLE_ID="com.pysdenis.kestrel"
CONFIG="${1:-release}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building kestrel-app ($CONFIG)…"
swift build -c "$CONFIG" --product kestrel-app
BIN="$(swift build -c "$CONFIG" --show-bin-path)/kestrel-app"

APP="$ROOT/dist/Kestrel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kestrel"

# App icon (generate on demand if missing — see scripts/make-icns.sh).
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "AppIcon.icns missing — generating…"
    bash "$ROOT/scripts/make-icns.sh" || echo "warning: icon generation failed; bundle will use the default icon"
fi
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Kestrel</string>
    <key>CFBundleDisplayName</key>     <string>Kestrel</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>Kestrel</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Regular app: shows the window and a Dock icon on launch, plus a menu-bar item.
         (Set LSUIElement to true for a pure menu-bar accessory once packaged.) -->
    <key>LSUIElement</key>             <false/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Denis Pyš. MIT.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so the bundle launches without a Developer ID.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign skipped"

echo "Built $APP"
echo "Run it with:  open \"$APP\""
