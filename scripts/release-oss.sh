#!/usr/bin/env bash
# Free OSS release: build the app, package an (unsigned) .dmg + .zip, and — only with
# --publish — cut a versioned GitHub Release the in-app updater can find.
#
# No Apple Developer account needed. The artifacts are ad-hoc signed but not notarized, so on
# *download* macOS quarantines them. Removing that is `xattr -dr com.apple.quarantine <app>`, or
# System Settings > Privacy & Security > Open Anyway. Right-click > Open no longer works: Apple
# dropped that bypass in macOS 15, so don't put it in user-facing instructions.
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

# gh's *active* account is a global setting and can silently be the wrong (read-only) one,
# which otherwise fails late with a confusing "workflow scope may be required" message. Check
# write access up front and point at the fix.
REPO_SLUG="$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"

# Pin gh to the repo owner's account via GH_TOKEN — independent of gh's global active account,
# which can silently revert to the wrong one. Mirrors the per-folder git credential helper.
# Falls back to the active account when the owner isn't a logged-in gh account (e.g. orgs).
OWNER="${REPO_SLUG%%/*}"
if [[ -n "$OWNER" ]] && _owner_token="$(gh auth token --user "$OWNER" 2>/dev/null)" && [[ -n "$_owner_token" ]]; then
    export GH_TOKEN="$_owner_token"
    echo "▸ Publishing as: $(gh api user --jq '.login' 2>/dev/null)"
fi

if [[ -n "$REPO_SLUG" ]]; then
    if [[ "$(gh api "repos/$REPO_SLUG" --jq '.permissions.push' 2>/dev/null)" != "true" ]]; then
        echo "✗ The active gh account ($(gh api user --jq '.login' 2>/dev/null)) can't push to $REPO_SLUG." >&2
        echo "  Switch to an account with write access, then re-run:" >&2
        echo "    gh auth switch --user <owner>" >&2
        exit 1
    fi
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "▸ Release $TAG exists — uploading/overwriting assets…"
    gh release upload "$TAG" "$DMG" "$ZIP" --clobber
else
    echo "▸ Creating GitHub Release ${TAG}…"
    gh release create "$TAG" "$DMG" "$ZIP" --title "Kestrel ${VERSION}" --generate-notes
fi

echo ""
echo "✓ Published $TAG. The in-app updater (Settings → Updates) will now find it."
