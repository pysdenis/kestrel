#!/usr/bin/env bash
# Free OSS release: build the app, package an (unsigned) .dmg + .zip, and — only with
# --publish — cut a versioned GitHub Release the in-app updater can find.
#
# No Apple Developer account needed. The artifacts are unsigned, so on *download* macOS
# quarantines them; friends open via right-click → Open (or `xattr -dr com.apple.quarantine`).
# Building from source instead (./scripts/build-app.sh) avoids Gatekeeper entirely.
#
#   bash scripts/release-oss.sh              # build artifacts, print the publish command
#   bash scripts/release-oss.sh --publish    # also create the GitHub Release (needs gh auth)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

VERSION="$(grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+"' Sources/KestrelCore/Version.swift | tr -d '"' | head -1)"
TAG="v${VERSION}"
APP="dist/Kestrel.app"
DMG="dist/Kestrel-${VERSION}.dmg"
ZIP="dist/Kestrel-${VERSION}.zip"

echo "▸ Building release bundle (v${VERSION})…"
bash scripts/build-app.sh release

echo "▸ Packaging .zip…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Packaging .dmg…"
rm -f "$DMG"
STAGE="dist/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Kestrel ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "✓ Artifacts:"
echo "  $DMG"
echo "  $ZIP"

if [[ "$PUBLISH" -eq 0 ]]; then
    cat <<NEXT

Not published. To cut the GitHub Release (the in-app updater reads the latest one):

  bash scripts/release-oss.sh --publish

or manually:

  gh release create ${TAG} "$DMG" "$ZIP" --title "Kestrel ${VERSION}" --generate-notes

NEXT
    exit 0
fi

command -v gh >/dev/null 2>&1 || { echo "✗ gh CLI not found — install it or publish manually." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ gh not authenticated — run: gh auth login" >&2; exit 1; }

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "▸ Release $TAG exists — uploading/overwriting assets…"
    gh release upload "$TAG" "$DMG" "$ZIP" --clobber
else
    echo "▸ Creating GitHub Release $TAG…"
    gh release create "$TAG" "$DMG" "$ZIP" --title "Kestrel ${VERSION}" --generate-notes
fi

echo ""
echo "✓ Published $TAG. The in-app updater (Settings → Updates) will now find it."
