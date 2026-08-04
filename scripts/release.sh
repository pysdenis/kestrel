#!/usr/bin/env bash
# One-shot Developer ID release: sign (hardened runtime) → notarize → staple → package a .dmg.
# Requires an Apple Developer account, a "Developer ID Application" cert in the keychain, and
# stored notarytool credentials. See docs/RELEASE.md. Nothing here uploads unless you set the
# env vars — running it without them just prints what's missing and exits.
#
#   SIGN_IDENTITY="Developer ID Application: Denis Pyš (TEAMID)" \
#   NOTARY_PROFILE="KESTREL_NOTARY" \
#   bash scripts/release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APP="dist/Kestrel.app"
VERSION="$(grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+"' Sources/KestrelCore/Version.swift | tr -d '"' | head -1)"
DMG="dist/Kestrel-${VERSION}.dmg"

fail() { echo "✗ $1" >&2; exit 1; }

[[ -n "$SIGN_IDENTITY" ]] || fail "Set SIGN_IDENTITY to your \"Developer ID Application: …\" identity (see: security find-identity -v -p codesigning)"
[[ -n "$NOTARY_PROFILE" ]] || fail "Set NOTARY_PROFILE to a stored notarytool profile (xcrun notarytool store-credentials …)"

echo "▸ Building release bundle…"
bash scripts/build-app.sh release

echo "▸ Signing with hardened runtime…"
# Sign nested code first, then the bundle. --options runtime is required for notarization.
find "$APP/Contents" -type f \( -name "*.dylib" -o -perm -u+x \) -not -path "*/MacOS/Kestrel" -print0 2>/dev/null \
    | xargs -0 -I{} codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" {} 2>/dev/null || true
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/Kestrel"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP" || fail "codesign verification failed"

echo "▸ Notarizing (this waits for Apple)…"
ZIP="dist/Kestrel-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait || fail "notarization failed"
rm -f "$ZIP"

echo "▸ Stapling…"
xcrun stapler staple "$APP"
spctl -a -vvv --type exec "$APP" || echo "warning: spctl assessment did not report accepted"

echo "▸ Packaging DMG…"
rm -f "$DMG"
STAGE="dist/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Kestrel" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

echo ""
echo "✓ Release ready: $DMG"
echo "  Notarized, stapled, and signed. Verify on a clean Mac with: spctl -a -vvv --type open $DMG"
